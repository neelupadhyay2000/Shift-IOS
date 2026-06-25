import Foundation
import Supabase

/// A point-in-time pull of every row the signed-in user can access, one array
/// per table. RLS scopes each select to the user's owned + collaborator events,
/// so a plain `select *` returns exactly the accessible rows.
nonisolated struct HydrationSnapshot {
    var events: [EventDTO] = []
    var tracks: [TrackDTO] = []
    var blocks: [BlockDTO] = []
    var vendors: [EventVendorDTO] = []
    var blockVendors: [BlockVendorDTO] = []
    var blockDependencies: [BlockDependencyDTO] = []
    var shiftRecords: [ShiftRecordDTO] = []

    init(
        events: [EventDTO] = [],
        tracks: [TrackDTO] = [],
        blocks: [BlockDTO] = [],
        vendors: [EventVendorDTO] = [],
        blockVendors: [BlockVendorDTO] = [],
        blockDependencies: [BlockDependencyDTO] = [],
        shiftRecords: [ShiftRecordDTO] = []
    ) {
        self.events = events
        self.tracks = tracks
        self.blocks = blocks
        self.vendors = vendors
        self.blockVendors = blockVendors
        self.blockDependencies = blockDependencies
        self.shiftRecords = shiftRecords
    }

    var isEmpty: Bool {
        events.isEmpty && tracks.isEmpty && blocks.isEmpty && vendors.isEmpty
            && blockVendors.isEmpty && blockDependencies.isEmpty && shiftRecords.isEmpty
    }
}

/// Source of a ``HydrationSnapshot`` — abstracted so `InitialHydrator`'s
/// upsert/wiring logic can be unit-tested with canned DTOs, no network.
protocol HydrationSource: Sendable {
    func fetchSnapshot() async throws -> HydrationSnapshot
}

/// Pulls pages from `fetchPage` (inclusive `[from, to]` bounds) until a page
/// shorter than `pageSize` signals the end, accumulating every row. A stable
/// total order in the underlying query is required so consecutive ranges
/// partition the result set without overlapping or skipping rows.
nonisolated func paginate<Row>(
    pageSize: Int,
    fetchPage: (_ from: Int, _ to: Int) async throws -> [Row]
) async rethrows -> [Row] {
    var all: [Row] = []
    var offset = 0
    while true {
        let page = try await fetchPage(offset, offset + pageSize - 1)
        all.append(contentsOf: page)
        if page.count < pageSize { break }
        offset += pageSize
    }
    return all
}

/// Supabase-backed source. Each table is fetched in `pageSize` batches via
/// PostgREST `range`, ordered by a stable key, so large datasets load without a
/// single huge query timing out or a single huge response spiking memory.
/// Nonisolated so the fetches run off the main actor.
///
/// `pageSize` must be ≤ the project's PostgREST `db-max-rows` (if set), otherwise
/// a capped full page would be mistaken for the last page.
nonisolated struct SupabaseHydrationSource: HydrationSource {
    private let client: SupabaseClient
    private let pageSize: Int

    init(client: SupabaseClient, pageSize: Int = 1000) {
        self.client = client
        self.pageSize = max(1, pageSize)
    }

    func fetchSnapshot() async throws -> HydrationSnapshot {
        // The seven table reads are independent — issue them concurrently instead
        // of serially. Latency drops from the sum of round-trips to the slowest
        // single one (the dominant cost of a full hydrate on every sign-in /
        // pull-to-refresh). The result is identical: each `try await` below still
        // surfaces the first error and the snapshot is assembled the same way.
        async let events = fetch("events", orderBy: "id") as [EventDTO]
        async let tracks = fetch("tracks", orderBy: "id") as [TrackDTO]
        async let blocks = fetch("blocks", orderBy: "id") as [BlockDTO]
        async let vendors = fetch("event_vendors", orderBy: "id") as [EventVendorDTO]
        async let blockVendors = fetch("block_vendors", orderBy: "block_id", "event_vendor_id") as [BlockVendorDTO]
        async let blockDependencies = fetch("block_dependencies", orderBy: "block_id", "depends_on_block_id") as [BlockDependencyDTO]
        async let shiftRecords = fetch("shift_records", orderBy: "id") as [ShiftRecordDTO]

        return HydrationSnapshot(
            events: try await events,
            tracks: try await tracks,
            blocks: try await blocks,
            vendors: try await vendors,
            blockVendors: try await blockVendors,
            blockDependencies: try await blockDependencies,
            shiftRecords: try await shiftRecords
        )
    }

    /// Paginated `select *` over `table`, restricted to live rows
    /// (`deleted_at is null`) and ordered by `first` (plus any `rest` columns) to
    /// form a stable total order for range paging.
    ///
    /// The tombstone filter is what separates a full hydrate from the delta pull:
    /// the delta deliberately *includes* `deleted_at` rows so the applier can turn
    /// them into local deletes, but the hydrator is upsert-only (it never deletes),
    /// so a tombstone in its snapshot would resurrect a row the user just deleted.
    private func fetch<Row: Decodable>(
        _ table: String,
        orderBy first: String,
        _ rest: String...
    ) async throws -> [Row] {
        try await paginate(pageSize: pageSize) { from, to in
            var query = self.client.from(table)
                .select()
                .is("deleted_at", value: nil)
                .order(first)
            for column in rest {
                query = query.order(column)
            }
            return try await query.range(from: from, to: to).execute().value
        }
    }
}
