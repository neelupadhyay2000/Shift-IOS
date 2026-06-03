import Foundation
import Testing
@testable import shiftTimeline

@Suite struct VendorInviteStatusTests {

    @Test func acceptedWhenRecordNamePresent() {
        #expect(VendorInviteStatus.of(invitedAt: nil, cloudKitRecordName: "rec_123") == .accepted)
        #expect(VendorInviteStatus.of(invitedAt: .now, cloudKitRecordName: "rec_123") == .accepted)
    }

    @Test func invitedWhenInvitedAtSetButNotAccepted() {
        #expect(VendorInviteStatus.of(invitedAt: .now, cloudKitRecordName: nil) == .invited)
        #expect(VendorInviteStatus.of(invitedAt: .now, cloudKitRecordName: "") == .invited)
    }

    @Test func notInvitedWhenNeither() {
        #expect(VendorInviteStatus.of(invitedAt: nil, cloudKitRecordName: nil) == .notInvited)
        #expect(VendorInviteStatus.of(invitedAt: nil, cloudKitRecordName: "") == .notInvited)
    }
}
