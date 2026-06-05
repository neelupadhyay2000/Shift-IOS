import Foundation
import Models
import Services
import Supabase

/// Supabase-backed `VendorRepositing`. Upserts the `event_vendors` row by `id`,
/// and manages block assignments as rows in the `block_vendors` junction table.
@MainActor
struct SupabaseVendorRepository: VendorRepositing {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func insert(_ vendor: VendorModel, into event: EventModel) async throws {
        try await client
            .from("event_vendors")
            .upsert(vendor.toDTO(eventID: event.id), onConflict: "id")
            .execute()
    }

    func fetch(id: UUID) async throws -> VendorModel? {
        let rows: [EventVendorDTO] = try await client
            .from("event_vendors")
            .select()
            .eq("id", value: id.uuidString)
            .execute()
            .value
        return rows.first?.makeModel()
    }

    func fetchAll(for event: EventModel) async throws -> [VendorModel] {
        let rows: [EventVendorDTO] = try await client
            .from("event_vendors")
            .select()
            .eq("event_id", value: event.id.uuidString)
            .execute()
            .value
        return rows.map { $0.makeModel() }
    }

    func delete(_ vendor: VendorModel) async throws {
        try await client
            .from("event_vendors")
            .delete()
            .eq("id", value: vendor.id.uuidString)
            .execute()
    }

    /// No-op: remote writes flush per mutating call (see `SupabaseEventRepository`).
    func save() async throws {}

    func assign(_ vendor: VendorModel, to block: TimeBlockModel) async throws {
        guard let eventID = vendor.event?.id else { throw ModelMappingError.missingEvent }
        let edge = BlockVendorDTO(blockID: block.id, eventVendorID: vendor.id, eventID: eventID)
        try await client
            .from("block_vendors")
            .upsert(edge, onConflict: "block_id,event_vendor_id")
            .execute()
    }

    func unassign(_ vendor: VendorModel, from block: TimeBlockModel) async throws {
        try await client
            .from("block_vendors")
            .delete()
            .eq("block_id", value: block.id.uuidString)
            .eq("event_vendor_id", value: vendor.id.uuidString)
            .execute()
    }
}
