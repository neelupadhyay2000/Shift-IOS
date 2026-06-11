import Foundation

/// Row in the Supabase `shift_records` table. Mirrors `ShiftRecord`, an
/// append-only audit entry for each shift applied to an event timeline.
///
/// `source_block_id` is null for global shifts not tied to a specific block.
/// `triggered_by` is coded as plain text (free-text column); the typed
/// `ShiftSource` conversion happens in the mapping layer.
///
/// The table's `snapshot jsonb` column has no `ShiftRecord` counterpart and is
/// neither read nor written by the client, so it is intentionally not modeled
/// here — unknown keys are ignored on decode, and omitting it on encode leaves
/// the column on its default.
nonisolated struct ShiftRecordDTO: Codable, Equatable {
    let id: UUID
    let eventID: UUID
    let sourceBlockID: UUID?
    let timestamp: PostgresTimestamp
    let deltaMinutes: Int
    let triggeredBy: String
    let createdAt: PostgresTimestamp?
    let updatedAt: PostgresTimestamp?
    let deletedAt: PostgresTimestamp?

    enum CodingKeys: String, CodingKey {
        case id
        case eventID = "event_id"
        case sourceBlockID = "source_block_id"
        case timestamp
        case deltaMinutes = "delta_minutes"
        case triggeredBy = "triggered_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(
        id: UUID,
        eventID: UUID,
        sourceBlockID: UUID? = nil,
        timestamp: PostgresTimestamp,
        deltaMinutes: Int,
        triggeredBy: String,
        createdAt: PostgresTimestamp? = nil,
        updatedAt: PostgresTimestamp? = nil,
        deletedAt: PostgresTimestamp? = nil
    ) {
        self.id = id
        self.eventID = eventID
        self.sourceBlockID = sourceBlockID
        self.timestamp = timestamp
        self.deltaMinutes = deltaMinutes
        self.triggeredBy = triggeredBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
