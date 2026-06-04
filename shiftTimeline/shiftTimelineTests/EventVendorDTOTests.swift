import Foundation
@testable import shiftTimeline
import Testing

@Suite("EventVendorDTO — coding")
struct EventVendorDTOTests {

    @Test("encodes columns in snake_case with role as raw text")
    func encodesSnakeCaseKeys() throws {
        let dto = EventVendorDTO(
            id: UUID(),
            eventID: UUID(),
            displayName: "Jane's Photography",
            role: "photographer",
            notificationThreshold: 600,
            hasAcknowledgedLatestShift: false
        )
        let json = try jsonObject(from: dto)
        #expect(json["event_id"] != nil)
        #expect(json["display_name"] as? String == "Jane's Photography")
        #expect(json["role"] as? String == "photographer")
        #expect(json["notification_threshold"] as? Int == 600)
        #expect(json["has_acknowledged_latest_shift"] as? Bool == false)
        #expect(json["displayName"] == nil)
    }

    @Test("omits nil profile_id and invite fields for a contact-only vendor")
    func omitsNilInviteFields() throws {
        let dto = EventVendorDTO(
            id: UUID(),
            eventID: UUID(),
            displayName: "DJ Mike",
            role: "dj",
            notificationThreshold: 300,
            hasAcknowledgedLatestShift: false
        )
        let json = try jsonObject(from: dto)
        #expect(json["profile_id"] == nil)
        #expect(json["invited_phone"] == nil)
        #expect(json["invited_email"] == nil)
        #expect(json["pending_shift_delta"] == nil)
        #expect(json["invited_at"] == nil)
        #expect(json["accepted_at"] == nil)
    }

    @Test("decodes an invited-but-unclaimed vendor (null profile_id)")
    func decodesInvitedVendor() throws {
        let id = UUID()
        let eventID = UUID()
        let json = """
        {
            "id": "\(id.uuidString)",
            "event_id": "\(eventID.uuidString)",
            "profile_id": null,
            "invited_phone": "+14155550101",
            "invited_email": null,
            "display_name": "Florist",
            "role": "florist",
            "notification_threshold": 900,
            "has_acknowledged_latest_shift": false,
            "pending_shift_delta": 12.5,
            "invited_at": "2026-06-04T16:00:00Z"
        }
        """
        let dto = try decodeDTO(EventVendorDTO.self, from: json)
        #expect(dto.id == id)
        #expect(dto.profileID == nil)
        #expect(dto.invitedPhone == "+14155550101")
        #expect(dto.invitedEmail == nil)
        #expect(dto.role == "florist")
        #expect(dto.notificationThreshold == 900)
        #expect(dto.pendingShiftDelta == 12.5)
        #expect(dto.invitedAt?.value == SupabaseTimestamp.date(from: "2026-06-04T16:00:00Z"))
    }

    @Test("round-trips a fully claimed vendor")
    func roundTrips() throws {
        let dto = EventVendorDTO(
            id: UUID(),
            eventID: UUID(),
            profileID: UUID(),
            invitedPhone: "+14155550101",
            invitedEmail: "v@example.com",
            displayName: "Vendor",
            role: "caterer",
            notificationThreshold: 600,
            hasAcknowledgedLatestShift: true,
            pendingShiftDelta: nil,
            invitedAt: fixedPGTimestamp,
            acceptedAt: fixedPGTimestamp,
            createdAt: fixedPGTimestamp,
            updatedAt: fixedPGTimestamp
        )
        #expect(try roundTrip(dto) == dto)
    }
}
