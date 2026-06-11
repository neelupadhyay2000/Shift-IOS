import Foundation
import Models
import Services
import TestSupport
import Testing
@testable import shiftTimeline

@Suite("Vendor invite — create event_vendors row")
@MainActor
struct VendorInviteServiceTests {

    /// Fixed instant so `invitedAt` is deterministic.
    private nonisolated static let invitedInstant = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeService(
        now: @escaping () -> Date = { invitedInstant }
    ) -> (VendorInviteService, FakeVendorRepository) {
        let repo = FakeVendorRepository()
        return (VendorInviteService(repository: repo, now: now), repo)
    }

    private func vendor(phone: String = "", email: String = "") -> VendorModel {
        VendorModel(name: "Avery", role: .photographer, phone: phone, email: email)
    }

    @Test func markInvitedStampsInvitedAtAndPersists() async throws {
        let (service, repo) = makeService()
        let vendor = vendor(phone: "555-0100")

        let lookup = try await service.markInvited(vendor)

        #expect(vendor.invitedAt == Self.invitedInstant)
        #expect(repo.saveCallCount == 1)
        #expect(lookup == .phone("555-0100"))
    }

    @Test func markInvitedPrefersPhoneOverEmail() async throws {
        let (service, _) = makeService()
        let lookup = try await service.markInvited(vendor(phone: "555-0100", email: "a@b.com"))
        #expect(lookup == .phone("555-0100"))
    }

    @Test func markInvitedFallsBackToEmail() async throws {
        let (service, _) = makeService()
        let vendor = vendor(email: "a@b.com")
        let lookup = try await service.markInvited(vendor)
        #expect(lookup == .email("a@b.com"))
        #expect(vendor.invitedAt == Self.invitedInstant)
    }

    @Test func markInvitedRejectsContactOnlyVendor() async throws {
        let (service, repo) = makeService()
        let vendor = vendor() // no phone, no email

        await #expect(throws: VendorInviteError.notInvitable) {
            try await service.markInvited(vendor)
        }
        #expect(vendor.invitedAt == nil, "A vendor that can't be invited must not be stamped")
        #expect(repo.saveCallCount == 0, "Nothing to persist when the invite is rejected")
    }

    @Test func reSendRefreshesInvitedAt() async throws {
        let earlier = Date(timeIntervalSince1970: 1_600_000_000)
        var clock = earlier
        let repo = FakeVendorRepository()
        let service = VendorInviteService(repository: repo, now: { clock })
        let vendor = vendor(phone: "555-0100")

        _ = try await service.markInvited(vendor)
        #expect(vendor.invitedAt == earlier)

        clock = Self.invitedInstant
        _ = try await service.markInvited(vendor)
        #expect(vendor.invitedAt == Self.invitedInstant, "Re-sending refreshes the invite timestamp")
        #expect(repo.saveCallCount == 2)
    }

    /// AC: inviting yields an `event_vendors` row with `profile_id` null and the
    /// invite fields populated. Asserted via the DTO the row syncs as.
    @Test func invitedRowProjectsWithNullProfileIDAndInviteFields() async throws {
        let (service, _) = makeService()
        let vendor = vendor(phone: "555-0100", email: "a@b.com")
        vendor.notificationThreshold = 900

        _ = try await service.markInvited(vendor)

        let eventID = UUID()
        let dto = vendor.toDTO(eventID: eventID)

        #expect(dto.profileID == nil)
        #expect(dto.acceptedAt == nil)
        #expect(dto.eventID == eventID)
        #expect(dto.invitedPhone == "555-0100")
        #expect(dto.invitedEmail == "a@b.com")
        #expect(dto.role == VendorRole.photographer.rawValue)
        #expect(dto.notificationThreshold == 900)
        #expect(dto.invitedAt?.value == Self.invitedInstant)
    }
}
