import Testing
import Foundation
import Contacts
@testable import shiftTimeline

@Suite("AppleSignInService")
struct AppleSignInServiceTests {

    // MARK: - Nonce generation

    @Test("generateNonce returns a non-empty string")
    func generateNonceIsNonEmpty() {
        let nonce = AppleSignInService.generateNonce()
        #expect(!nonce.isEmpty)
    }

    @Test("generateNonce returns a string longer than 20 characters")
    func generateNonceLengthIsAdequate() {
        let nonce = AppleSignInService.generateNonce()
        #expect(nonce.count > 20)
    }

    @Test("generateNonce produces a unique value on each call")
    func generateNonceIsUnique() {
        let a = AppleSignInService.generateNonce()
        let b = AppleSignInService.generateNonce()
        #expect(a != b)
    }

    @Test("generateNonce contains only URL-safe base64 characters")
    func generateNonceIsURLSafe() {
        let nonce = AppleSignInService.generateNonce()
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        #expect(nonce.unicodeScalars.allSatisfy { allowedCharacters.contains($0) })
    }

    // MARK: - SHA-256

    @Test("sha256 produces the correct hex digest for a known input")
    func sha256KnownInput() {
        // echo -n "hello" | shasum -a 256
        let result = AppleSignInService.sha256("hello")
        #expect(result == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }

    @Test("sha256 returns a 64-character hex string")
    func sha256OutputIs64Chars() {
        let result = AppleSignInService.sha256("shift-nonce-test")
        #expect(result.count == 64)
    }

    @Test("sha256 produces different digests for different inputs")
    func sha256DifferentInputsDifferentOutputs() {
        #expect(AppleSignInService.sha256("a") != AppleSignInService.sha256("b"))
    }

    // MARK: - Initialization

    @MainActor
    @Test("AppleSignInService initializes with a SupabaseClient")
    func initializesWithClient() throws {
        let url = try #require(URL(string: "https://wrhrpyinkcopqsibmkrf.supabase.co"))
        let provider = SupabaseClientProvider(supabaseURL: url, supabaseKey: "test-anon-key")
        let service = AppleSignInService(client: provider.client)
        _ = service
    }
}

// MARK: - First-time vs returning user detection

@Suite("AppleSignInService — first-time detection")
struct AppleSignInFirstTimeDetectionTests {

    @Test("isFirstTimeSignIn returns true when fullName has a givenName")
    func firstTimeWhenGivenNamePresent() {
        var components = PersonNameComponents()
        components.givenName = "Ada"
        #expect(AppleSignInService.isFirstTimeSignIn(fullName: components))
    }

    @Test("isFirstTimeSignIn returns true when fullName has a familyName")
    func firstTimeWhenFamilyNamePresent() {
        var components = PersonNameComponents()
        components.familyName = "Lovelace"
        #expect(AppleSignInService.isFirstTimeSignIn(fullName: components))
    }

    @Test("isFirstTimeSignIn returns true when fullName has both given and family name")
    func firstTimeWhenBothNamesPresent() {
        var components = PersonNameComponents()
        components.givenName = "Ada"
        components.familyName = "Lovelace"
        #expect(AppleSignInService.isFirstTimeSignIn(fullName: components))
    }

    @Test("isFirstTimeSignIn returns false when fullName is nil")
    func returningUserWhenFullNameNil() {
        #expect(!AppleSignInService.isFirstTimeSignIn(fullName: nil))
    }

    @Test("isFirstTimeSignIn returns false when fullName has no name components")
    func returningUserWhenAllComponentsEmpty() {
        let components = PersonNameComponents()
        #expect(!AppleSignInService.isFirstTimeSignIn(fullName: components))
    }
}

// MARK: - Display name formatting

@Suite("AppleSignInService — displayName")
struct AppleSignInDisplayNameTests {

    @Test("displayName formats given and family name into a non-empty string")
    func formatsFullName() {
        var components = PersonNameComponents()
        components.givenName = "Ada"
        components.familyName = "Lovelace"
        let result = AppleSignInService.displayName(from: components)
        #expect(result != nil)
        #expect(result?.isEmpty == false)
    }

    @Test("displayName returns a non-empty string when only givenName is present")
    func formatsGivenNameOnly() {
        var components = PersonNameComponents()
        components.givenName = "Ada"
        let result = AppleSignInService.displayName(from: components)
        #expect(result != nil)
        #expect(result?.isEmpty == false)
    }

    @Test("displayName returns nil when components is nil")
    func returnsNilForNilComponents() {
        #expect(AppleSignInService.displayName(from: nil) == nil)
    }

    @Test("displayName returns nil when all name components are empty")
    func returnsNilForEmptyComponents() {
        let components = PersonNameComponents()
        #expect(AppleSignInService.displayName(from: components) == nil)
    }
}
