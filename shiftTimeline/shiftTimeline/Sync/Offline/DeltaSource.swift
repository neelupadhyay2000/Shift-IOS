import Foundation
import Supabase

/// Source of a delta ``HydrationSnapshot`` — the rows that changed since a
/// watermark. Abstracted (like ``HydrationSource``) so ``DeltaReconciler``'s
/// merge logic can be unit-tested with canned DTOs, no network.
protocol DeltaSource: Sendable {
    /// Rows changed since `since` (`nil` → everything, e.g. a first pull). The
    /// result includes soft-deleted rows so tombstones propagate — the applier
    /// turns a `deleted_at` row into a local delete.
    func fetchDelta(since: Date?) async throws -> HydrationSnapshot
}

/// Supabase-backed delta source. Mirrors ``SupabaseHydrationSource`` but bounds
/// each table by the watermark, paging via PostgREST `range` over a stable order
/// so a long-backgrounded catch-up can't time out or spike memory. Nonisolated
/// so the fetches run off the main actor.
nonisolated struct SupabaseDeltaSource: DeltaSource {
    private let client: SupabaseClient
    private let pageSize: Int

    init(client: SupabaseClient, pageSize: Int = 1000) {
        self.client = client
        self.pageSize = max(1, pageSize)
    }

    func fetchDelta(since: Date?) async throws -> HydrationSnapshot {
        let bound = since.map(SupabaseTimestamp.string(from:))
        return HydrationSnapshot(
            events: try await fetchUpdated("events", since: bound, orderBy: "id"),
            tracks: try await fetchUpdated("tracks", since: bound, orderBy: "id"),
            blocks: try await fetchUpdated("blocks", since: bound, orderBy: "id"),
            vendors: try await fetchUpdated("event_vendors", since: bound, orderBy: "id"),
            blockVendors: try await fetchCreated("block_vendors", since: bound, orderBy: "block_id", "event_vendor_id"),
            blockDependencies: try await fetchCreated("block_dependencies", since: bound, orderBy: "block_id", "depends_on_block_id"),
            shiftRecords: try await fetchUpdated("shift_records", since: bound, orderBy: "id")
        )
    }

    /// Main tables: rows whose `updated_at` is past the watermark. The server
    /// trigger bumps `updated_at` on every change — including a soft-delete — so
    /// this naturally includes tombstones (the applier turns `deleted_at` into a
    /// local delete).
    private func fetchUpdated<Row: Decodable>(
        _ table: String, since: String?, orderBy first: String, _ rest: String...
    ) async throws -> [Row] {
        try await paginate(pageSize: pageSize) { from, to in
            let selected = self.client.from(table).select()
            let bounded = since.map { selected.gt("updated_at", value: $0) } ?? selected
            var query = bounded.order(first)
            for column in rest { query = query.order(column) }
            return try await query.range(from: from, to: to).execute().value
        }
    }

    /// Junction tables have no `updated_at` — they're immutable rows that are
    /// created or (with SHIFT-606's soft-delete) tombstoned. Here we pull rows
    /// created since the watermark: new assignments/dependencies. Removal
    /// propagation arrives with SHIFT-606 — extend this to also match
    /// `deleted_at > since`.
    private func fetchCreated<Row: Decodable>(
        _ table: String, since: String?, orderBy first: String, _ rest: String...
    ) async throws -> [Row] {
        try await paginate(pageSize: pageSize) { from, to in
            let selected = self.client.from(table).select()
            let bounded = since.map { selected.gt("created_at", value: $0) } ?? selected
            var query = bounded.order(first)
            for column in rest { query = query.order(column) }
            return try await query.range(from: from, to: to).execute().value
        }
    }
}
