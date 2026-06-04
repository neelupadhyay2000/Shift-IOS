import Foundation
import Models

@MainActor
extension ShiftRecord {
    /// Projects this shift record to its wire form.
    /// `source_block_id` is null for global shifts not tied to a block.
    /// - Throws: `ModelMappingError.missingEvent` if the record is detached.
    func toDTO() throws -> ShiftRecordDTO {
        guard let eventID = event?.id else { throw ModelMappingError.missingEvent }
        return ShiftRecordDTO(
            id: id,
            eventID: eventID,
            sourceBlockID: sourceBlock?.id,
            timestamp: PostgresTimestamp(timestamp),
            deltaMinutes: deltaMinutes,
            triggeredBy: triggeredBy.rawValue,
            createdAt: nil,
            updatedAt: nil,
            deletedAt: nil
        )
    }
}

@MainActor
extension ShiftRecordDTO {
    /// Builds a fresh `ShiftRecord` with this row's scalar fields (relationships unwired).
    func makeModel() -> ShiftRecord {
        let model = ShiftRecord(
            deltaMinutes: deltaMinutes,
            triggeredBy: ShiftSource(rawValue: triggeredBy) ?? .manual
        )
        apply(to: model)
        return model
    }

    /// Overwrites `model`'s scalar fields from this row (upsert by id).
    func apply(to model: ShiftRecord) {
        model.id = id
        model.timestamp = timestamp.value
        model.deltaMinutes = deltaMinutes
        model.triggeredBy = ShiftSource(rawValue: triggeredBy) ?? .manual
    }

    /// Wires the event and optional source-block relationships by id.
    func linkRelationships(
        _ model: ShiftRecord,
        events: [UUID: EventModel],
        blocks: [UUID: TimeBlockModel]
    ) {
        model.event = events[eventID]
        model.sourceBlock = sourceBlockID.flatMap { blocks[$0] }
    }
}
