import Testing
import Foundation
@testable import shiftTimeline

@Suite("PhoneAuthService — normalizePhone")
struct PhoneNormalizationTests {

    @Test("strips spaces and dashes from a 10-digit US number and adds +1")
    func stripSpacesAndDashes() {
        #expect(PhoneAuthService.normalizePhone("555 123-4567") == "+15551234567")
    }

    @Test("strips parentheses and dots from a 10-digit US number and adds +1")
    func stripParensAndDots() {
        #expect(PhoneAuthService.normalizePhone("(555) 123.4567") == "+15551234567")
    }

    @Test("adds +1 prefix to a bare 10-digit US number")
    func adds1To10Digits() {
        #expect(PhoneAuthService.normalizePhone("5551234567") == "+15551234567")
    }

    @Test("adds + to an 11-digit number that starts with 1")
    func addsPlusTo11Digits() {
        #expect(PhoneAuthService.normalizePhone("15551234567") == "+15551234567")
    }

    @Test("leaves an existing E.164 number unchanged")
    func leavesE164Unchanged() {
        #expect(PhoneAuthService.normalizePhone("+447911123456") == "+447911123456")
    }

    @Test("strips formatting from an E.164 number while preserving the + prefix")
    func stripsFormattingFromE164() {
        #expect(PhoneAuthService.normalizePhone("+44 791 112 3456") == "+447911123456")
    }
}

@Suite("PhoneAuthService — isValidE164")
struct PhoneE164ValidationTests {

    @Test("accepts a valid 11-digit US E.164 number")
    func validUSNumber() {
        #expect(PhoneAuthService.isValidE164("+15551234567"))
    }

    @Test("accepts a valid international E.164 number")
    func validInternationalNumber() {
        #expect(PhoneAuthService.isValidE164("+447911123456"))
    }

    @Test("accepts the minimum valid length (8 chars: + and 7 digits)")
    func acceptsMinimumLength() {
        #expect(PhoneAuthService.isValidE164("+1234567"))
    }

    @Test("accepts the maximum valid length (16 chars: + and 15 digits)")
    func acceptsMaximumLength() {
        #expect(PhoneAuthService.isValidE164("+123456789012345"))
    }

    @Test("rejects a number without a leading +")
    func rejectsWithoutPlus() {
        #expect(!PhoneAuthService.isValidE164("15551234567"))
    }

    @Test("rejects an empty string")
    func rejectsEmpty() {
        #expect(!PhoneAuthService.isValidE164(""))
    }

    @Test("rejects a number that is too short (fewer than 7 digits)")
    func rejectsTooShort() {
        #expect(!PhoneAuthService.isValidE164("+123456"))
    }

    @Test("rejects a number that is too long (more than 15 digits)")
    func rejectsTooLong() {
        #expect(!PhoneAuthService.isValidE164("+1234567890123456"))
    }

    @Test("rejects a number containing non-digit characters after +")
    func rejectsNonDigits() {
        #expect(!PhoneAuthService.isValidE164("+1abc1234567"))
    }
}

@Suite("PhoneAuthService — initialization")
struct PhoneAuthServiceInitTests {

    @MainActor
    @Test("initializes with a SupabaseClient")
    func initializesWithClient() throws {
        let url = try #require(URL(string: "https://wrhrpyinkcopqsibmkrf.supabase.co"))
        let provider = SupabaseClientProvider(supabaseURL: url, supabaseKey: "test-anon-key")
        let service = PhoneAuthService(client: provider.client)
        _ = service
    }
}
