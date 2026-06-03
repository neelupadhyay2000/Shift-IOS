import Foundation
import Testing
@testable import shiftTimeline

@Suite struct VendorParticipantMatcherTests {

    private let vendorA = VendorRef(id: UUID(), email: "alice@studio.com", phone: "(555) 111-2222")
    private let vendorB = VendorRef(id: UUID(), email: "Bob@DJ.com", phone: "")

    @Test func matchesByExactEmailCaseInsensitive() {
        let participants = [ParticipantInfo(recordName: "rec_bob", email: "bob@dj.com", phone: nil)]
        let matches = VendorParticipantMatcher.match(participants: participants, vendors: [vendorA, vendorB])
        #expect(matches == [VendorMatch(vendorID: vendorB.id, recordName: "rec_bob")])
    }

    @Test func matchesByPhoneAcrossCountryCode() {
        // CloudKit returns E.164 (+1...), vendor stored a formatted local number.
        let participants = [ParticipantInfo(recordName: "rec_alice", email: nil, phone: "+15551112222")]
        let matches = VendorParticipantMatcher.match(participants: participants, vendors: [vendorA, vendorB])
        #expect(matches == [VendorMatch(vendorID: vendorA.id, recordName: "rec_alice")])
    }

    @Test func skipsParticipantWithNoRecordName() {
        // No userRecordID yet = not accepted; nothing to stamp.
        let participants = [ParticipantInfo(recordName: nil, email: "alice@studio.com", phone: nil)]
        let matches = VendorParticipantMatcher.match(participants: participants, vendors: [vendorA])
        #expect(matches.isEmpty)
    }

    @Test func omitsUnmatchedParticipants() {
        let participants = [ParticipantInfo(recordName: "rec_x", email: "stranger@nowhere.com", phone: "+19998887777")]
        let matches = VendorParticipantMatcher.match(participants: participants, vendors: [vendorA, vendorB])
        #expect(matches.isEmpty)
    }

    @Test func matchesMultipleParticipants() {
        let participants = [
            ParticipantInfo(recordName: "rec_alice", email: nil, phone: "5551112222"),
            ParticipantInfo(recordName: "rec_bob", email: "bob@dj.com", phone: nil),
        ]
        let matches = VendorParticipantMatcher.match(participants: participants, vendors: [vendorA, vendorB])
        #expect(matches.contains(VendorMatch(vendorID: vendorA.id, recordName: "rec_alice")))
        #expect(matches.contains(VendorMatch(vendorID: vendorB.id, recordName: "rec_bob")))
        #expect(matches.count == 2)
    }

    @Test func phoneMatchRequiresMinimumLength() {
        // Short numbers must not loosely match on suffix.
        #expect(VendorParticipantMatcher.phoneMatches("123", "0123") == false)
        #expect(VendorParticipantMatcher.phoneMatches("+15551112222", "5551112222") == true)
        #expect(VendorParticipantMatcher.phoneMatches("5551112222", "5551110000") == false)
    }
}
