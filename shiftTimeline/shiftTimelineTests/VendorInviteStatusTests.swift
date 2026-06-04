import Foundation
import Testing
@testable import shiftTimeline

@Suite struct VendorInviteStatusTests {

    @Test func acceptedWhenProfileIdPresent() {
        #expect(VendorInviteStatus.of(invitedAt: nil, profileId: "uid_123") == .accepted)
        #expect(VendorInviteStatus.of(invitedAt: .now, profileId: "uid_123") == .accepted)
    }

    @Test func invitedWhenInvitedAtSetButNotAccepted() {
        #expect(VendorInviteStatus.of(invitedAt: .now, profileId: nil) == .invited)
        #expect(VendorInviteStatus.of(invitedAt: .now, profileId: "") == .invited)
    }

    @Test func notInvitedWhenNeither() {
        #expect(VendorInviteStatus.of(invitedAt: nil, profileId: nil) == .notInvited)
        #expect(VendorInviteStatus.of(invitedAt: nil, profileId: "") == .notInvited)
    }
}
