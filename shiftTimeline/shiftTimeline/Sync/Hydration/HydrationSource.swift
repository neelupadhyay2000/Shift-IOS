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

/// Supabase-backed source: one RLS-scoped `select *` per table. Nonisolated so
/// the fetches run off the main actor. Pagination/batching is layered on in
/// SHIFT-595; this fetches each table whole.
nonisolated struct SupabaseHydrationSource: HydrationSource {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func fetchSnapshot() async throws -> HydrationSnapshot {
        HydrationSnapshot(
            events: try await fetch("events"),
            tracks: try await fetch("tracks"),
            blocks: try await fetch("blocks"),
            vendors: try await fetch("event_vendors"),
            blockVendors: try await fetch("block_vendors"),
            blockDependencies: try await fetch("block_dependencies"),
            shiftRecords: try await fetch("shift_records")
        )
    }

    private func fetch<Row: Decodable>(_ table: String) async throws -> [Row] {
        try await client.from(table).select().execute().value
    }
}
