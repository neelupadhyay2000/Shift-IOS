import Foundation
import Models
import Services
import Supabase

/// Supabase-backed `ShiftRecordRepositing`. Upserts the append-only
/// `shift_records` row by `id`, denormalizing `event_id` from the event passed
/// on insert and `source_block_id` from the record's own block reference.
@MainActor
struct SupabaseShiftRecordRepository: ShiftRecordRepositing {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func insert(_ record: ShiftRecord, into event: EventModel) async throws {
        let dto = record.toDTO(eventID: event.id, sourceBlockID: record.sourceBlock?.id)
        try await client
            .from("shift_records")
            .upsert(dto, onConflict: "id")
            .execute()
    }

    func fetch(id: UUID) async throws -> ShiftRecord? {
        let rows: [ShiftRecordDTO] = try await client
            .from("shift_records")
            .select()
            .eq("id", value: id.uuidString)
            .execute()
            .value
        return rows.first?.makeModel()
    }

    func fetchAll(for event: EventModel) async throws -> [ShiftRecord] {
        let rows: [ShiftRecordDTO] = try await client
            .from("shift_records")
            .select()
            .eq("event_id", value: event.id.uuidString)
            .execute()
            .value
        return rows.map { $0.makeModel() }
    }

    func delete(_ record: ShiftRecord) async throws {
        try await client
            .from("shift_records")
            .delete()
            .eq("id", value: record.id.uuidString)
            .execute()
    }

    /// No-op: remote writes flush per mutating call (see `SupabaseEventRepository`).
    func save() async throws {}
}
