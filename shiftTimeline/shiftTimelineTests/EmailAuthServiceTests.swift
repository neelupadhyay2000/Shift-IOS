import Foundation
@testable import shiftTimeline
import Testing

@Suite("EmailAuthService — normalizeEmail")
struct EmailNormalizationTests {

    @Test("trims surrounding whitespace and newlines")
    func trimsWhitespace() {
        #expect(EmailAuthService.normalizeEmail("  vendor@example.com \n") == "vendor@example.com")
    }

    @Test("lowercases so it matches the case-insensitive invite claim")
    func lowercases() {
        #expect(EmailAuthService.normalizeEmail("Vendor@Example.COM") == "vendor@example.com")
    }

    @Test("leaves an already-normalized address unchanged")
    func leavesNormalizedUnchanged() {
        #expect(EmailAuthService.normalizeEmail("a.b+tag@sub.example.co") == "a.b+tag@sub.example.co")
    }
}

@Suite("EmailAuthService — isValidEmail")
struct EmailValidationTests {

    @Test("accepts a plain address")
    func acceptsPlain() {
        #expect(EmailAuthService.isValidEmail("vendor@example.com"))
    }

    @Test("accepts plus-tagged and subdomained addresses")
    func acceptsComplex() {
        #expect(EmailAuthService.isValidEmail("a.b+tag@mail.sub.example.co"))
    }

    @Test("rejects an address with no @")
    func rejectsNoAt() {
        #expect(!EmailAuthService.isValidEmail("vendor.example.com"))
    }

    @Test("rejects an address with no domain")
    func rejectsNoDomain() {
        #expect(!EmailAuthService.isValidEmail("vendor@"))
    }

    @Test("rejects an address with no TLD")
    func rejectsNoTLD() {
        #expect(!EmailAuthService.isValidEmail("vendor@example"))
    }

    @Test("rejects an empty string and a bare @")
    func rejectsEmptyAndBareAt() {
        #expect(!EmailAuthService.isValidEmail(""))
        #expect(!EmailAuthService.isValidEmail("@"))
    }

    @Test("rejects internal whitespace")
    func rejectsWhitespace() {
        #expect(!EmailAuthService.isValidEmail("ven dor@example.com"))
    }
}

@Suite("EmailAuthService — isValidOTPToken")
struct EmailOTPTokenTests {

    @Test("accepts a 6-digit token")
    func acceptsSixDigits() {
        #expect(EmailAuthService.isValidOTPToken("123456"))
    }

    @Test("rejects tokens that aren't exactly 6 digits")
    func rejectsWrongLengthOrNonDigits() {
        #expect(!EmailAuthService.isValidOTPToken("12345"))
        #expect(!EmailAuthService.isValidOTPToken("1234567"))
        #expect(!EmailAuthService.isValidOTPToken("12345a"))
        #expect(!EmailAuthService.isValidOTPToken(""))
        #expect(!EmailAuthService.isValidOTPToken(" 12345"))
    }
}

@Suite("EmailAuthError — localized descriptions")
struct EmailAuthErrorTests {

    @Test("every case has a non-empty localized description")
    func descriptionsPresent() {
        #expect(EmailAuthError.invalidEmail.errorDescription?.isEmpty == false)
        #expect(EmailAuthError.invalidOTPToken.errorDescription?.isEmpty == false)
        #expect(EmailAuthError.sessionMissing.errorDescription?.isEmpty == false)
    }
}

@Suite("EmailAuthService — initialization")
struct EmailAuthServiceInitTests {

    @MainActor
    @Test("initializes with a SupabaseClient")
    func initializesWithClient() throws {
        let url = try #require(URL(string: "https://example.supabase.co"))
        let provider = SupabaseClientProvider(supabaseURL: url, supabaseKey: "test-anon-key")
        _ = EmailAuthService(client: provider.client)
    }
}
