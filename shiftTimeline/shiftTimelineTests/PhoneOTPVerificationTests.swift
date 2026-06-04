import Testing
import Foundation
@testable import shiftTimeline

@Suite("PhoneAuthService — isValidOTPToken")
struct OTPTokenValidationTests {

    @Test("accepts a 6-digit token")
    func acceptsSixDigits() {
        #expect(PhoneAuthService.isValidOTPToken("123456"))
    }

    @Test("rejects a token with fewer than 6 digits")
    func rejectsFiveDigits() {
        #expect(!PhoneAuthService.isValidOTPToken("12345"))
    }

    @Test("rejects a token with more than 6 digits")
    func rejectsSevenDigits() {
        #expect(!PhoneAuthService.isValidOTPToken("1234567"))
    }

    @Test("rejects an empty string")
    func rejectsEmpty() {
        #expect(!PhoneAuthService.isValidOTPToken(""))
    }

    @Test("rejects a token containing a non-digit character")
    func rejectsNonDigit() {
        #expect(!PhoneAuthService.isValidOTPToken("12345a"))
    }

    @Test("rejects a token that is all spaces")
    func rejectsAllSpaces() {
        #expect(!PhoneAuthService.isValidOTPToken("      "))
    }

    @Test("rejects a token with leading or trailing spaces")
    func rejectsSpacePadded() {
        #expect(!PhoneAuthService.isValidOTPToken(" 12345"))
        #expect(!PhoneAuthService.isValidOTPToken("12345 "))
    }
}

@Suite("PhoneAuthError — localized descriptions")
struct PhoneAuthErrorDescriptionTests {

    @Test("invalidPhoneNumber has a non-nil localized description")
    func invalidPhoneNumberHasDescription() {
        #expect(PhoneAuthError.invalidPhoneNumber.errorDescription != nil)
    }

    @Test("invalidOTPToken has a non-nil localized description")
    func invalidOTPTokenHasDescription() {
        #expect(PhoneAuthError.invalidOTPToken.errorDescription != nil)
    }

    @Test("sessionMissing has a non-nil localized description")
    func sessionMissingHasDescription() {
        #expect(PhoneAuthError.sessionMissing.errorDescription != nil)
    }
}
