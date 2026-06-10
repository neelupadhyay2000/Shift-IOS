import Foundation
@testable import shiftTimeline
import Testing

@Suite("WaitlistEntryDTO — coding")
struct WaitlistEntryDTOTests {

    @Test("encodes columns in snake_case")
    func encodesSnakeCaseKeys() throws {
        let dto = WaitlistEntryDTO(
            profileID: UUID(),
            interestRole: "vendor",
            category: "dj",
            region: "Toronto, ON"
        )
        let json = try jsonObject(from: dto)
        #expect(json["profile_id"] != nil)
        #expect(json["interest_role"] as? String == "vendor")
        #expect(json["category"] as? String == "dj")
        #expect(json["region"] as? String == "Toronto, ON")
        #expect(json["profileID"] == nil)
        #expect(json["interestRole"] == nil)
    }

    @Test("encodes explicit null category so a planner upsert clears a stale vendor category")
    func encodesExplicitNullCategory() throws {
        let dto = WaitlistEntryDTO(
            profileID: UUID(),
            interestRole: "planner",
            category: nil,
            region: ""
        )
        let json = try jsonObject(from: dto)
        #expect(json["category"] is NSNull)
    }

    @Test("encodes explicit null deleted_at so re-joining resurrects a soft-deleted row")
    func encodesExplicitNullDeletedAt() throws {
        let dto = WaitlistEntryDTO(
            profileID: UUID(),
            interestRole: "vendor",
            category: "caterer",
            region: "Ottawa, ON"
        )
        let json = try jsonObject(from: dto)
        #expect(json["deleted_at"] is NSNull)
    }

    @Test("never encodes server-managed timestamps")
    func omitsServerTimestamps() throws {
        let dto = WaitlistEntryDTO(
            profileID: UUID(),
            interestRole: "both",
            category: "florist",
            region: "Ottawa, ON",
            createdAt: fixedPGTimestamp,
            updatedAt: fixedPGTimestamp
        )
        let json = try jsonObject(from: dto)
        #expect(json["created_at"] == nil)
        #expect(json["updated_at"] == nil)
    }

    @Test("decodes a PostgREST row, ignoring extra columns like id")
    func decodesRow() throws {
        let profileID = UUID()
        let json = """
        {
            "id": "\(UUID().uuidString)",
            "profile_id": "\(profileID.uuidString)",
            "interest_role": "vendor",
            "category": "photographer",
            "region": "Toronto, ON",
            "created_at": "2026-06-04T16:00:00Z",
            "updated_at": "2026-06-04T16:00:00Z",
            "deleted_at": null
        }
        """
        let dto = try decodeDTO(WaitlistEntryDTO.self, from: json)
        #expect(dto.profileID == profileID)
        #expect(dto.interestRole == "vendor")
        #expect(dto.category == "photographer")
        #expect(dto.region == "Toronto, ON")
        #expect(dto.deletedAt == nil)
        #expect(dto.updatedAt?.value == SupabaseTimestamp.date(from: "2026-06-04T16:00:00Z"))
    }

    @Test("decodes a planner row with null category")
    func decodesNullCategory() throws {
        let json = """
        {
            "profile_id": "\(UUID().uuidString)",
            "interest_role": "planner",
            "category": null,
            "region": ""
        }
        """
        let dto = try decodeDTO(WaitlistEntryDTO.self, from: json)
        #expect(dto.interestRole == "planner")
        #expect(dto.category == nil)
        #expect(dto.region.isEmpty)
    }

    @Test("decodes a soft-deleted row with its tombstone")
    func decodesTombstone() throws {
        let json = """
        {
            "profile_id": "\(UUID().uuidString)",
            "interest_role": "vendor",
            "category": "dj",
            "region": "Toronto, ON",
            "deleted_at": "2026-06-04T16:00:00Z"
        }
        """
        let dto = try decodeDTO(WaitlistEntryDTO.self, from: json)
        #expect(dto.deletedAt?.value == SupabaseTimestamp.date(from: "2026-06-04T16:00:00Z"))
    }

    @Test("round-trips a payload")
    func roundTrips() throws {
        let dto = WaitlistEntryDTO(
            profileID: UUID(),
            interestRole: "both",
            category: "custom",
            region: "Vancouver, BC"
        )
        #expect(try roundTrip(dto) == dto)
    }
}
