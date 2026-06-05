import Foundation
import Models
import Services
import Supabase

/// Supabase-backed `BlockRepositing`. Upserts the block row by `id` (denormalizing
/// `event_id` from the parent track's event), and manages dependency edges as
/// rows in the `block_dependencies` junction table.
@MainActor
struct SupabaseBlockRepository: BlockRepositing {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func insert(_ block: TimeBlockModel, into track: TimelineTrack) async throws {
        guard let eventID = track.event?.id else { throw ModelMappingError.missingEvent }
        try await client
            .from("blocks")
            .upsert(block.toDTO(trackID: track.id, eventID: eventID), onConflict: "id")
            .execute()
    }

    func fetch(id: UUID) async throws -> TimeBlockModel? {
        let rows: [BlockDTO] = try await client
            .from("blocks")
            .select()
            .eq("id", value: id.uuidString)
            .execute()
            .value
        return rows.first?.makeModel()
    }

    func fetchAll(for track: TimelineTrack) async throws -> [TimeBlockModel] {
        let rows: [BlockDTO] = try await client
            .from("blocks")
            .select()
            .eq("track_id", value: track.id.uuidString)
            .execute()
            .value
        return rows
            .map { $0.makeModel() }
            .sorted { $0.scheduledStart < $1.scheduledStart }
    }

    func delete(_ block: TimeBlockModel) async throws {
        try await client
            .from("blocks")
            .delete()
            .eq("id", value: block.id.uuidString)
            .execute()
    }

    /// No-op: remote writes flush per mutating call (see `SupabaseEventRepository`).
    func save() async throws {}

    func addDependency(_ dependency: TimeBlockModel, to block: TimeBlockModel) async throws {
        guard let eventID = block.track?.event?.id else { throw ModelMappingError.missingEvent }
        let edge = BlockDependencyDTO(blockID: block.id, dependsOnBlockID: dependency.id, eventID: eventID)
        try await client
            .from("block_dependencies")
            .upsert(edge, onConflict: "block_id,depends_on_block_id")
            .execute()
    }

    func removeDependency(_ dependency: TimeBlockModel, from block: TimeBlockModel) async throws {
        try await client
            .from("block_dependencies")
            .delete()
            .eq("block_id", value: block.id.uuidString)
            .eq("depends_on_block_id", value: dependency.id.uuidString)
            .execute()
    }
}
