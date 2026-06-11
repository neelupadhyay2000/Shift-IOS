import Foundation
import Models
import Services
import TestSupport
import Testing
@testable import shiftTimeline

@Suite("Vendor invite claim — link on sign-in")
@MainActor
struct VendorInviteClaimServiceTests {

    /// Fixed instant so `acceptedAt` is deterministic.
    private nonisolated static let claimInstant = Date(timeIntervalSince1970: 1_700_000_000)
    private nonisolated static let invitedInstant = Date(timeIntervalSince1970: 1_690_000_000)
    private nonisolated static let profileID = UUID(uuidString: "33333333-3333-3333-3333-333333333333") ?? UUID()

    private func makeService(
        now: @escaping () -> Date = { claimInstant }
    ) -> (VendorInviteClaimService, FakeVendorRepository) {
        let repo = FakeVendorRepository()
        return (VendorInviteClaimService(repository: repo, now: now), repo)
    }

    /// An invited (but unclaimed) vendor.
    private func invited(phone: String = "", email: String = "") -> VendorModel {
        let vendor = VendorModel(name: "Avery", role: .photographer, phone: phone, email: email)
        vendor.invitedAt = Self.invitedInstant
        return vendor
    }

    private func identity(phone: String? = nil, email: String? = nil) -> VendorInviteClaimIdentity {
        VendorInviteClaimIdentity(profileID: Self.profileID, phone: phone, email: email)
    }

    @Test func linksMatchingPhoneInviteAndFlipsStatusToAccepted() async throws {
        let (service, repo) = makeService()
        let vendor = invited(phone: "(415) 555-0101")

        let claimed = try await service.claimMatchingInvites(
            for: identity(phone: "14155550101"),
            among: [vendor]
        )

        #expect(claimed.map(\.id) == [vendor.id])
        #expect(vendor.profileId == Self.profileID)
        #expect(vendor.acceptedAt == Self.claimInstant)
        #expect(repo.saveCallCount == 1)
        #expect(
            VendorInviteStatus.of(invitedAt: vendor.invitedAt, profileId: vendor.profileId?.uuidString) == .accepted,
            "Setting profile_id must flip the status to accepted"
        )
    }

    @Test func linksMatchingEmailInvite() async throws {
        let (service, _) = makeService()
        let vendor = invited(email: "Jane@Example.com")

        let claimed = try await service.claimMatchingInvites(
            for: identity(email: "jane@example.com"),
            among: [vendor]
        )

        #expect(claimed.count == 1)
        #expect(vendor.profileId == Self.profileID)
        #expect(vendor.acceptedAt == Self.claimInstant)
    }

    @Test func leavesNonMatchingInviteUntouched() async throws {
        let (service, repo) = makeService()
        let vendor = invited(phone: "4155550101")

        let claimed = try await service.claimMatchingInvites(
            for: identity(phone: "9998887777"),
            among: [vendor]
        )

        #expect(claimed.isEmpty)
        #expect(vendor.profileId == nil)
        #expect(vendor.acceptedAt == nil)
        #expect(repo.saveCallCount == 0, "Nothing to persist when no row matches")
    }

    @Test func neverReLinksAnAlreadyClaimedRow() async throws {
        let (service, repo) = makeService()
        let vendor = invited(phone: "4155550101")
        let existingProfile = UUID()
        let existingAccept = Date(timeIntervalSince1970: 1_650_000_000)
        vendor.profileId = existingProfile
        vendor.acceptedAt = existingAccept

        let claimed = try await service.claimMatchingInvites(
            for: identity(phone: "4155550101"),
            among: [vendor]
        )

        #expect(claimed.isEmpty)
        #expect(vendor.profileId == existingProfile, "A claimed row must not be re-linked to a new profile")
        #expect(vendor.acceptedAt == existingAccept)
        #expect(repo.saveCallCount == 0)
    }

    @Test func ignoresContactOnlyVendorThatWasNeverInvited() async throws {
        let (service, repo) = makeService()
        // Has a matching phone but was never invited (invitedAt nil).
        let vendor = VendorModel(name: "Contact", role: .custom, phone: "4155550101")

        let claimed = try await service.claimMatchingInvites(
            for: identity(phone: "4155550101"),
            among: [vendor]
        )

        #expect(claimed.isEmpty)
        #expect(vendor.profileId == nil)
        #expect(repo.saveCallCount == 0)
    }

    @Test func claimsOnlyTheMatchingRowsAmongMany() async throws {
        let (service, repo) = makeService()
        let mineByEmail = invited(email: "me@x.com")
        let someoneElse = invited(email: "other@x.com")
        let mineByPhone = invited(phone: "4155550101")

        let claimed = try await service.claimMatchingInvites(
            for: identity(phone: "4155550101", email: "me@x.com"),
            among: [mineByEmail, someoneElse, mineByPhone]
        )

        #expect(Set(claimed.map(\.id)) == [mineByEmail.id, mineByPhone.id])
        #expect(mineByEmail.profileId == Self.profileID)
        #expect(mineByPhone.profileId == Self.profileID)
        #expect(someoneElse.profileId == nil)
        #expect(repo.saveCallCount == 1, "A batch claim persists exactly once")
    }

    /// AC: a claimed row projects to the wire with `profile_id` + `accepted_at` set.
    @Test func claimedRowProjectsProfileAndAcceptedAt() async throws {
        let (service, _) = makeService()
        let vendor = invited(phone: "4155550101")

        _ = try await service.claimMatchingInvites(
            for: identity(phone: "4155550101"),
            among: [vendor]
        )

        let eventID = UUID()
        let dto = vendor.toDTO(eventID: eventID)
        #expect(dto.profileID == Self.profileID)
        #expect(dto.acceptedAt?.value == Self.claimInstant)
    }
}
