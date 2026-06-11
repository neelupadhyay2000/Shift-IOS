import Foundation
import Supabase

/// Production ``OutboxSending`` — replays one outbox item to Supabase.
///
/// Insert/update **upsert** the decoded payload DTO keyed by `id` (composite key
/// for the junction tables), so a re-send (after a transient failure, or a crash
/// between a successful send and the local delete) converges onto the same row
/// instead of duplicating it. Deletes remove by `id` (main tables) or by the
/// composite key carried in the payload (junctions). The payload is the exact
/// DTO JSON the enqueue layer captured, so it decodes straight back into the
/// table's DTO.
@MainActor
struct SupabaseOutboxSender: OutboxSending {
    private let client: SupabaseClient
    private let decoder = JSONDecoder()

    init(client: SupabaseClient) {
        self.client = client
    }

    func send(_ item: OutboxItem) async throws {
        switch item.operation {
        case .insert, .update:
            try await upsert(item)
        case .delete:
            try await softDelete(item)
        }
    }

    private func upsert(_ item: OutboxItem) async throws {
        guard let payload = item.payload else { throw OutboxSendError.missingPayload(table: item.table) }
        let table = client.from(item.table)
        switch item.table {
        case "events":
            try await table.upsert(decode(EventDTO.self, payload), onConflict: "id").execute()
        case "tracks":
            try await table.upsert(decode(TrackDTO.self, payload), onConflict: "id").execute()
        case "blocks":
            try await table.upsert(decode(BlockDTO.self, payload), onConflict: "id").execute()
        case "event_vendors":
            try await table.upsert(decode(EventVendorDTO.self, payload), onConflict: "id").execute()
        case "shift_records":
            try await table.upsert(decode(ShiftRecordDTO.self, payload), onConflict: "id").execute()
        case "block_vendors":
            try await table.upsert(decode(BlockVendorDTO.self, payload), onConflict: "block_id,event_vendor_id").execute()
        case "block_dependencies":
            try await table.upsert(decode(BlockDependencyDTO.self, payload), onConflict: "block_id,depends_on_block_id").execute()
        default:
            throw OutboxSendError.unknownTable(item.table)
        }
    }

    /// A delete is a **soft-delete**: set `deleted_at` rather than
    /// removing the row, so the tombstone survives in the table and a device that
    /// was offline still learns of the deletion via the delta (`deleted_at`/
    /// `updated_at > since`). The `updated_at` trigger bumps on this update, so the
    /// tombstone carries a fresh server time for LWW. Old tombstones are reaped by
    /// ``TombstonePurger``.
    private func softDelete(_ item: OutboxItem) async throws {
        let patch = ["deleted_at": SupabaseTimestamp.string(from: Date())]
        switch item.table {
        case "events", "tracks", "blocks", "event_vendors", "shift_records":
            try await client.from(item.table)
                .update(patch)
                .eq("id", value: item.rowID.uuidString)
                .execute()
        case "block_vendors":
            guard let payload = item.payload else { throw OutboxSendError.missingPayload(table: item.table) }
            let dto = try decode(BlockVendorDTO.self, payload)
            try await client.from(item.table)
                .update(patch)
                .eq("block_id", value: dto.blockID.uuidString)
                .eq("event_vendor_id", value: dto.eventVendorID.uuidString)
                .execute()
        case "block_dependencies":
            guard let payload = item.payload else { throw OutboxSendError.missingPayload(table: item.table) }
            let dto = try decode(BlockDependencyDTO.self, payload)
            try await client.from(item.table)
                .update(patch)
                .eq("block_id", value: dto.blockID.uuidString)
                .eq("depends_on_block_id", value: dto.dependsOnBlockID.uuidString)
                .execute()
        default:
            throw OutboxSendError.unknownTable(item.table)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }
}

enum OutboxSendError: Error, Equatable {
    case missingPayload(table: String)
    case unknownTable(String)
}
