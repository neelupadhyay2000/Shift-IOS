import Foundation
@testable import shiftTimeline
import Testing

@Suite("TrackDTO — coding")
struct TrackDTOTests {

    @Test("encodes columns in snake_case")
    func encodesSnakeCaseKeys() throws {
        let dto = TrackDTO(id: UUID(), eventID: UUID(), name: "Photography", sortOrder: 2, isDefault: false)
        let json = try jsonObject(from: dto)
        #expect(json["event_id"] != nil)
        #expect(json["sort_order"] as? Int == 2)
        #expect(json["is_default"] as? Bool == false)
        #expect(json["eventId"] == nil)
        #expect(json["sortOrder"] == nil)
    }

    @Test("omits nil sync metadata")
    func omitsNilMetadata() throws {
        let dto = TrackDTO(id: UUID(), eventID: UUID(), name: "Main", sortOrder: 0, isDefault: true)
        let json = try jsonObject(from: dto)
        #expect(json["created_at"] == nil)
        #expect(json["updated_at"] == nil)
        #expect(json["deleted_at"] == nil)
    }

    @Test("decodes a Postgres-style row")
    func decodesPostgresRow() throws {
        let id = UUID()
        let eventID = UUID()
        let json = """
        {
            "id": "\(id.uuidString)",
            "event_id": "\(eventID.uuidString)",
            "name": "Catering",
            "sort_order": 5,
            "is_default": false,
            "created_at": "2026-06-04T16:00:00Z",
            "updated_at": "2026-06-04T16:00:00Z",
            "deleted_at": null
        }
        """
        let dto = try decodeDTO(TrackDTO.self, from: json)
        #expect(dto.id == id)
        #expect(dto.eventID == eventID)
        #expect(dto.name == "Catering")
        #expect(dto.sortOrder == 5)
        #expect(dto.deletedAt == nil)
        #expect(dto.createdAt?.value == SupabaseTimestamp.date(from: "2026-06-04T16:00:00Z"))
    }

    @Test("round-trips")
    func roundTrips() throws {
        let dto = TrackDTO(
            id: UUID(),
            eventID: UUID(),
            name: "Main",
            sortOrder: 1,
            isDefault: true,
            createdAt: fixedPGTimestamp,
            updatedAt: fixedPGTimestamp
        )
        #expect(try roundTrip(dto) == dto)
    }
}
