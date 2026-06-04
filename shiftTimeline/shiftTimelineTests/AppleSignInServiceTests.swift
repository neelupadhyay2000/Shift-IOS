import Testing
import Foundation
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
