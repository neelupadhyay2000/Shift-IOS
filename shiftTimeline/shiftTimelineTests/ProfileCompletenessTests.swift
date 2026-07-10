import Foundation
@testable import shiftTimeline
import Testing

@Suite("ProfileCompleteness — required-field rules")
struct ProfileCompletenessTests {

    // Rule (updated 2026-07-10): name, a valid email, AND a valid phone are
    // required for EVERY account — one person, one account, uniqueness enforced
    // across both channels, so both must be present.

    private let goodEmail = "neel@example.com"
    private let goodPhone = "+16475551234"

    @Test("a name, valid email, and valid phone is complete")
    func completeProfile() {
        #expect(ProfileCompleteness.missingFields(name: "Neel", email: goodEmail, phone: goodPhone).isEmpty)
        #expect(ProfileCompleteness.isComplete(name: "Neel", email: goodEmail, phone: goodPhone))
    }

    @Test("missing name is reported")
    func missingName() {
        let missing = ProfileCompleteness.missingFields(name: nil, email: goodEmail, phone: goodPhone)
        #expect(missing == [.name])
        #expect(!ProfileCompleteness.isComplete(name: nil, email: goodEmail, phone: goodPhone))
    }

    @Test("blank / whitespace name counts as missing")
    func blankName() {
        #expect(ProfileCompleteness.missingFields(name: "   \n", email: goodEmail, phone: goodPhone) == [.name])
    }

    @Test("missing email is reported (phone-signup before they add one)")
    func missingEmail() {
        let missing = ProfileCompleteness.missingFields(name: "Neel", email: nil, phone: goodPhone)
        #expect(missing == [.email])
    }

    @Test("malformed email counts as missing")
    func malformedEmail() {
        #expect(ProfileCompleteness.missingFields(name: "Neel", email: "not-an-email", phone: goodPhone) == [.email])
        #expect(ProfileCompleteness.missingFields(name: "Neel", email: "  ", phone: goodPhone) == [.email])
    }

    @Test("missing phone is reported (email-signup before they add one)")
    func missingPhone() {
        let missing = ProfileCompleteness.missingFields(name: "Neel", email: goodEmail, phone: nil)
        #expect(missing == [.phone])
        #expect(!ProfileCompleteness.isComplete(name: "Neel", email: goodEmail, phone: nil))
    }

    @Test("malformed phone counts as missing")
    func malformedPhone() {
        #expect(ProfileCompleteness.missingFields(name: "Neel", email: goodEmail, phone: "123") == [.phone])
        #expect(ProfileCompleteness.missingFields(name: "Neel", email: goodEmail, phone: "  ") == [.phone])
    }

    @Test("all missing are reported together")
    func allMissing() {
        let missing = ProfileCompleteness.missingFields(name: nil, email: nil, phone: nil)
        #expect(missing == [.name, .email, .phone])
        #expect(!ProfileCompleteness.isComplete(name: nil, email: nil, phone: nil))
    }

    @Test("surrounding whitespace on valid values is tolerated")
    func trimsFields() {
        #expect(ProfileCompleteness.isComplete(
            name: "Neel",
            email: "  neel@example.com  ",
            phone: "  +1 647 555 1234  "
        ))
    }

    // A US 10-digit number normalizes to +1XXXXXXXXXX and must count as valid, so
    // an email user typing their number without a country code isn't stuck.
    @Test("a bare 10-digit US number is accepted via normalization")
    func acceptsBareUSNumber() {
        #expect(ProfileCompleteness.isComplete(name: "Neel", email: goodEmail, phone: "6475551234"))
    }
}

// MARK: - IdentifierStatus

@Suite("IdentifierStatus — signup and edit predicates")
struct IdentifierStatusTests {

    /// The signup-entry gate: block only a stored-second-credential collision, and
    /// never a verified login (that's a returning user) or a free identifier.
    @Test("a verified login does not block signup")
    func verifiedLoginAllowsSignup() {
        let status = IdentifierStatus(
            emailInUse: true, phoneInUse: false,
            emailIsMine: false, phoneIsMine: false,
            emailIsAuth: true, phoneIsAuth: false
        )
        #expect(status.emailBlocksSignup == false)
    }

    @Test("a stored-only second credential blocks signup")
    func storedSecondaryBlocksSignup() {
        let status = IdentifierStatus(
            emailInUse: true, phoneInUse: false,
            emailIsMine: false, phoneIsMine: false,
            emailIsAuth: false, phoneIsAuth: false
        )
        #expect(status.emailBlocksSignup)
    }

    @Test("a free identifier does not block signup")
    func freeAllowsSignup() {
        #expect(IdentifierStatus.free.emailBlocksSignup == false)
        #expect(IdentifierStatus.free.phoneBlocksSignup == false)
    }

    /// The edit/complete gate: taken by *someone else*, but never the caller's own.
    @Test("a credential the caller already owns is not a collision")
    func ownCredentialIsNotTaken() {
        let status = IdentifierStatus(
            emailInUse: true, phoneInUse: false,
            emailIsMine: true, phoneIsMine: false,
            emailIsAuth: true, phoneIsAuth: false
        )
        #expect(status.emailTakenByOther == false)
    }

    @Test("a credential owned by another account is taken")
    func othersCredentialIsTaken() {
        let status = IdentifierStatus(
            emailInUse: false, phoneInUse: true,
            emailIsMine: false, phoneIsMine: false,
            emailIsAuth: false, phoneIsAuth: true
        )
        #expect(status.phoneTakenByOther)
    }

    @Test("the wire contract decodes the RPC's snake_case columns")
    func decodesRPCRow() throws {
        let json = """
        {
          "email_in_use": true, "phone_in_use": false,
          "email_is_mine": false, "phone_is_mine": false,
          "email_is_auth": true, "phone_is_auth": false
        }
        """
        let status = try JSONDecoder().decode(IdentifierStatus.self, from: Data(json.utf8))
        #expect(status.emailInUse)
        #expect(status.emailIsAuth)
        #expect(status.phoneInUse == false)
    }
}
