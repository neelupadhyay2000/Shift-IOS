import Foundation
import Models
import Services
import Supabase

/// Supabase-backed `EventRepositing`.
///
/// Mutations upsert the event row by `id` (`owner_id` resolved from the current
/// session); reads materialize detached `EventModel` snapshots from the fetched
/// rows. This is the remote half — local write-through is layered on
/// separately, so `save()` is a no-op here (each mutation flushes immediately).
@MainActor
struct SupabaseEventRepository: EventRepositing {
    private let client: SupabaseClient
    private let currentOwnerID: @MainActor () -> UUID?

    init(client: SupabaseClient, currentOwnerID: @escaping @MainActor () -> UUID?) {
        self.client = client
        self.currentOwnerID = currentOwnerID
    }

    func insert(_ event: EventModel) async throws {
        guard let ownerID = currentOwnerID() else { throw SupabaseRepositoryError.notAuthenticated }
        try await client
            .from("events")
            .upsert(event.toDTO(ownerID: ownerID), onConflict: "id")
            .execute()
    }

    func fetch(id: UUID) async throws -> EventModel? {
        let rows: [EventDTO] = try await client
            .from("events")
            .select()
            .eq("id", value: id.uuidString)
            .execute()
            .value
        return rows.first?.makeModel()
    }

    func fetchAll() async throws -> [EventModel] {
        let rows: [EventDTO] = try await client
            .from("events")
            .select()
            .execute()
            .value
        return rows.map { $0.makeModel() }
    }

    func delete(_ event: EventModel) async throws {
        try await client
            .from("events")
            .delete()
            .eq("id", value: event.id.uuidString)
            .execute()
    }

    /// No-op: remote writes flush per mutating call. The write-through
    /// repository drives change-tracked syncing on `save()`.
    func save() async throws {}
}
