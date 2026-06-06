import Foundation
import Testing
@testable import shiftTimeline

@Suite("Vendor invite claim matcher (SHIFT-627)")
struct VendorInviteClaimTests {

    // MARK: - Email

    @Test func matchesEmailCaseInsensitively() {
        #expect(VendorInviteClaim.matches(
            invitedPhone: nil, invitedEmail: "Jane@Example.com",
            identityPhone: nil, identityEmail: "jane@example.com"
        ))
    }

    @Test func matchesEmailIgnoringSurroundingWhitespace() {
        #expect(VendorInviteClaim.matches(
            invitedPhone: nil, invitedEmail: "  jane@example.com  ",
            identityPhone: nil, identityEmail: "jane@example.com"
        ))
    }

    @Test func rejectsDifferentEmail() {
        #expect(!VendorInviteClaim.matches(
            invitedPhone: nil, invitedEmail: "a@x.com",
            identityPhone: nil, identityEmail: "b@x.com"
        ))
    }

    // MARK: - Phone (normalized to E.164, matching the OTP sign-in flow)

    @Test func matchesFormattedLocalNumberAgainstE164WithoutPlus() {
        // Planner typed "(415) 555-0101"; Supabase signed the vendor in as 14155550101.
        #expect(VendorInviteClaim.matches(
            invitedPhone: "(415) 555-0101", invitedEmail: nil,
            identityPhone: "14155550101", identityEmail: nil
        ))
    }

    @Test func matchesAcrossPlusAndSpacingVariants() {
        #expect(VendorInviteClaim.matches(
            invitedPhone: "+1 415-555-0101", invitedEmail: nil,
            identityPhone: "+14155550101", identityEmail: nil
        ))
    }

    @Test func rejectsDifferentPhone() {
        #expect(!VendorInviteClaim.matches(
            invitedPhone: "4155550101", invitedEmail: nil,
            identityPhone: "4155550102", identityEmail: nil
        ))
    }

    // MARK: - Either contact suffices

    @Test func emailMatchSucceedsEvenWhenPhoneDiffers() {
        #expect(VendorInviteClaim.matches(
            invitedPhone: "4155550101", invitedEmail: "j@x.com",
            identityPhone: "9998887777", identityEmail: "j@x.com"
        ))
    }

    // MARK: - Missing contact never matches

    @Test func inviteWithNoContactNeverMatches() {
        #expect(!VendorInviteClaim.matches(
            invitedPhone: nil, invitedEmail: nil,
            identityPhone: "4155550101", identityEmail: "j@x.com"
        ))
    }

    @Test func emptyContactStringsNeverMatch() {
        #expect(!VendorInviteClaim.matches(
            invitedPhone: "", invitedEmail: "",
            identityPhone: "4155550101", identityEmail: "j@x.com"
        ))
    }

    @Test func identityWithoutContactNeverMatches() {
        #expect(!VendorInviteClaim.matches(
            invitedPhone: "4155550101", invitedEmail: "j@x.com",
            identityPhone: nil, identityEmail: nil
        ))
    }
}
