import Foundation
@testable import shiftTimeline
import Testing

@Suite("DeviceTokenDTO — coding")
struct DeviceTokenDTOTests {

    @Test("encodes columns in snake_case")
    func encodesSnakeCaseKeys() throws {
        let dto = DeviceTokenDTO(
            id: UUID(),
            profileID: UUID(),
            apnsToken: "a1b2c3",
            environment: "sandbox"
        )
        let json = try jsonObject(from: dto)
        #expect(json["profile_id"] != nil)
        #expect(json["apns_token"] as? String == "a1b2c3")
        #expect(json["environment"] as? String == "sandbox")
        #expect(json["apnsToken"] == nil)
    }

    @Test("decodes a Postgres-style row")
    func decodesPostgresRow() throws {
        let id = UUID()
        let profileID = UUID()
        let json = """
        {
            "id": "\(id.uuidString)",
            "profile_id": "\(profileID.uuidString)",
            "apns_token": "deadbeef",
            "environment": "prod",
            "created_at": "2026-06-04T16:00:00Z",
            "updated_at": "2026-06-04T16:00:00Z"
        }
        """
        let dto = try decodeDTO(DeviceTokenDTO.self, from: json)
        #expect(dto.id == id)
        #expect(dto.profileID == profileID)
        #expect(dto.apnsToken == "deadbeef")
        #expect(dto.environment == "prod")
    }

    @Test("round-trips")
    func roundTrips() throws {
        let dto = DeviceTokenDTO(
            id: UUID(),
            profileID: UUID(),
            apnsToken: "token",
            environment: "sandbox",
            createdAt: fixedPGTimestamp,
            updatedAt: fixedPGTimestamp
        )
        #expect(try roundTrip(dto) == dto)
    }
}
