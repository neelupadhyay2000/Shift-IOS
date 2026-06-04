import Foundation
@testable import shiftTimeline
import Testing

@Suite("ShiftRecordDTO — coding")
struct ShiftRecordDTOTests {

    @Test("encodes columns in snake_case with triggered_by as raw text")
    func encodesSnakeCaseKeys() throws {
        let dto = ShiftRecordDTO(
            id: UUID(),
            eventID: UUID(),
            sourceBlockID: UUID(),
            timestamp: fixedPGTimestamp,
            deltaMinutes: -15,
            triggeredBy: "manual"
        )
        let json = try jsonObject(from: dto)
        #expect(json["event_id"] != nil)
        #expect(json["source_block_id"] != nil)
        #expect(json["delta_minutes"] as? Int == -15)
        #expect(json["triggered_by"] as? String == "manual")
        #expect(json["timestamp"] as? String != nil)
        // snapshot is intentionally not modeled.
        #expect(json["snapshot"] == nil)
    }

    @Test("omits nil source_block_id for a global shift")
    func omitsNilSourceBlock() throws {
        let dto = ShiftRecordDTO(
            id: UUID(),
            eventID: UUID(),
            timestamp: fixedPGTimestamp,
            deltaMinutes: 10,
            triggeredBy: "dependency"
        )
        let json = try jsonObject(from: dto)
        #expect(json["source_block_id"] == nil)
        #expect(json["created_at"] == nil)
    }

    @Test("decodes a Postgres-style row and ignores the unmodeled snapshot column")
    func decodesPostgresRow() throws {
        let id = UUID()
        let eventID = UUID()
        let json = """
        {
            "id": "\(id.uuidString)",
            "event_id": "\(eventID.uuidString)",
            "source_block_id": null,
            "timestamp": "2026-06-04T19:30:00.250Z",
            "delta_minutes": 5,
            "triggered_by": "watch",
            "snapshot": { "anything": [1, 2, 3] }
        }
        """
        let dto = try decodeDTO(ShiftRecordDTO.self, from: json)
        #expect(dto.id == id)
        #expect(dto.eventID == eventID)
        #expect(dto.sourceBlockID == nil)
        #expect(dto.deltaMinutes == 5)
        #expect(dto.triggeredBy == "watch")
        #expect(dto.timestamp.value == SupabaseTimestamp.date(from: "2026-06-04T19:30:00.250Z"))
    }

    @Test("round-trips")
    func roundTrips() throws {
        let dto = ShiftRecordDTO(
            id: UUID(),
            eventID: UUID(),
            sourceBlockID: UUID(),
            timestamp: fixedPGTimestamp,
            deltaMinutes: -3,
            triggeredBy: "undo",
            createdAt: fixedPGTimestamp,
            updatedAt: fixedPGTimestamp
        )
        #expect(try roundTrip(dto) == dto)
    }
}
