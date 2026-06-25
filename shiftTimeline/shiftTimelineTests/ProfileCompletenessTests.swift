import Foundation
@testable import shiftTimeline
import Testing

@Suite("ProfileCompleteness — required-field rules")
struct ProfileCompletenessTests {

    // Rule (2026-06-25): name required for ALL accounts; a valid email required
    // for ALL accounts (auto-present for email-signups, collected for phone-
    // signups). Phone is never gated.

    @Test("a name and a valid email is complete")
    func completeProfile() {
        #expect(ProfileCompleteness.missingFields(name: "Neel", email: "neel@example.com").isEmpty)
        #expect(ProfileCompleteness.isComplete(name: "Neel", email: "neel@example.com"))
    }

    @Test("missing name is reported")
    func missingName() {
        let missing = ProfileCompleteness.missingFields(name: nil, email: "neel@example.com")
        #expect(missing == [.name])
        #expect(!ProfileCompleteness.isComplete(name: nil, email: "neel@example.com"))
    }

    @Test("blank / whitespace name counts as missing")
    func blankName() {
        #expect(ProfileCompleteness.missingFields(name: "   \n", email: "a@b.co") == [.name])
    }

    @Test("missing email is reported (phone-signup before they add one)")
    func missingEmail() {
        let missing = ProfileCompleteness.missingFields(name: "Neel", email: nil)
        #expect(missing == [.email])
    }

    @Test("malformed email counts as missing")
    func malformedEmail() {
        #expect(ProfileCompleteness.missingFields(name: "Neel", email: "not-an-email") == [.email])
        #expect(ProfileCompleteness.missingFields(name: "Neel", email: "  ") == [.email])
    }

    @Test("both missing are reported together")
    func bothMissing() {
        let missing = ProfileCompleteness.missingFields(name: nil, email: nil)
        #expect(missing == [.name, .email])
        #expect(!ProfileCompleteness.isComplete(name: nil, email: nil))
    }

    @Test("surrounding whitespace on a valid email is tolerated")
    func trimsEmail() {
        #expect(ProfileCompleteness.isComplete(name: "Neel", email: "  neel@example.com  "))
    }
}
