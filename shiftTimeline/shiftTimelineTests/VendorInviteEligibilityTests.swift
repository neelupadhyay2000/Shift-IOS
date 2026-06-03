import Foundation
import Testing
@testable import shiftTimeline

@Suite struct VendorInviteEligibilityTests {

    @Test func phonePreferredWhenBothPresent() {
        let lookup = VendorInviteEligibility.preferredLookup(phone: "555-123-4567", email: "a@b.com")
        #expect(lookup == .phone("555-123-4567"))
    }

    @Test func emailWhenOnlyEmail() {
        let lookup = VendorInviteEligibility.preferredLookup(phone: "", email: "a@b.com")
        #expect(lookup == .email("a@b.com"))
    }

    @Test func phoneWhenOnlyPhone() {
        let lookup = VendorInviteEligibility.preferredLookup(phone: "(555) 123-4567", email: "")
        #expect(lookup == .phone("(555) 123-4567"))
    }

    @Test func nilWhenNeitherOrWhitespace() {
        #expect(VendorInviteEligibility.preferredLookup(phone: "", email: "") == nil)
        #expect(VendorInviteEligibility.preferredLookup(phone: "   ", email: "  ") == nil)
    }

    @Test func trimsWhitespace() {
        #expect(VendorInviteEligibility.preferredLookup(phone: "  5551234567 ", email: "") == .phone("5551234567"))
        #expect(VendorInviteEligibility.preferredLookup(phone: "", email: " a@b.com ") == .email("a@b.com"))
    }
}
