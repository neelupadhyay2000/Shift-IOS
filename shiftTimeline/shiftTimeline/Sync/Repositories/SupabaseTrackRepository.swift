import Foundation
import Models
import Services
import Supabase

/// Supabase-backed `TrackRepositing`. Upserts the track row by `id`, denormalizing
/// the parent `event_id` from the `event` passed on insert.
@MainActor
struct SupabaseTrackRepository: TrackRepositing {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func insert(_ track: TimelineTrack, into event: EventModel) async throws {
        try await client
            .from("tracks")
            .upsert(track.toDTO(eventID: event.id), onConflict: "id")
            .execute()
    }

    func fetch(id: UUID) async throws -> TimelineTrack? {
        let rows: [TrackDTO] = try await client
            .from("tracks")
            .select()
            .eq("id", value: id.uuidString)
            .execute()
            .value
        return rows.first?.makeModel()
    }

    func fetchAll(for event: EventModel) async throws -> [TimelineTrack] {
        let rows: [TrackDTO] = try await client
            .from("tracks")
            .select()
            .eq("event_id", value: event.id.uuidString)
            .execute()
            .value
        return rows.map { $0.makeModel() }
    }

    func delete(_ track: TimelineTrack) async throws {
        try await client
            .from("tracks")
            .delete()
            .eq("id", value: track.id.uuidString)
            .execute()
    }

    /// No-op: remote writes flush per mutating call (see `SupabaseEventRepository`).
    func save() async throws {}
}
