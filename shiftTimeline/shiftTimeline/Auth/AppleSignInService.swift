import AuthenticationServices
import CryptoKit
import Foundation
import Supabase
import UIKit

// MARK: - Error

enum AppleSignInError: Error, Sendable {
    case missingIdentityToken
    case cancelled
}

// MARK: - Service

/// Drives the Sign in with Apple flow and exchanges the Apple identity token
/// with Supabase's Apple OAuth provider.
///
/// Call `signIn()` from any `@MainActor` context. The method is `async throws`
/// and suspends until the Apple authorization sheet completes.
///
/// The raw nonce is passed to Supabase; the SHA-256 hash is given to Apple so
/// the server can verify the nonce was not tampered with in transit.
@MainActor
final class AppleSignInService: NSObject {

    private let client: SupabaseClient

    // Held strongly to prevent ASAuthorizationController deallocation mid-flow.
    private var authorizationController: ASAuthorizationController?

    private var currentNonce: String?
    private var continuation: CheckedContinuation<Session, Error>?

    init(client: SupabaseClient) {
        self.client = client
    }

    // MARK: - Public API

    /// Initiates the Sign in with Apple sheet and exchanges the returned
    /// identity token with Supabase's Apple provider.
    ///
    /// - Returns: The established Supabase `Session`.
    /// - Throws: `AppleSignInError` or a Supabase `AuthError`.
    func signIn() async throws -> Session {
        let nonce = Self.generateNonce()
        currentNonce = nonce

        return try await withCheckedThrowingContinuation { [self] continuation in
            self.continuation = continuation

            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = Self.sha256(nonce)

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            authorizationController = controller
            controller.performRequests()
        }
    }

    // MARK: - Nonce Utilities

    /// Generates a cryptographically random URL-safe base64 nonce.
    nonisolated static func generateNonce(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            // SecRandomCopyBytes should never fail on Apple hardware;
            // fall back to a UUID-derived value as a last resort.
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Returns the SHA-256 hex digest of `input`.
    nonisolated static func sha256(_ input: String) -> String {
        let hash = SHA256.hash(data: Data(input.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Private

    private func handleAuthorization(_ authorization: ASAuthorization) async {
        defer {
            continuation = nil
            currentNonce = nil
            authorizationController = nil
        }

        guard
            let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = appleCredential.identityToken,
            let idToken = String(data: tokenData, encoding: .utf8),
            let nonce = currentNonce
        else {
            continuation?.resume(throwing: AppleSignInError.missingIdentityToken)
            return
        }

        do {
            let session = try await client.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
            )
            continuation?.resume(returning: session)
        } catch {
            continuation?.resume(throwing: error)
        }
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AppleSignInService: ASAuthorizationControllerDelegate {

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor [self] in
            await handleAuthorization(authorization)
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor [self] in
            let mapped: Error
            if let authError = error as? ASAuthorizationError,
               authError.code == .canceled {
                mapped = AppleSignInError.cancelled
            } else {
                mapped = error
            }
            continuation?.resume(throwing: mapped)
            continuation = nil
            currentNonce = nil
            authorizationController = nil
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AppleSignInService: ASAuthorizationControllerPresentationContextProviding {

    /// The system always calls this on the main thread; `MainActor.assumeIsolated`
    /// asserts that invariant to the Swift 6 concurrency checker.
    nonisolated func presentationAnchor(
        for controller: ASAuthorizationController
    ) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
                .flatMap { $0.windows.first(where: \.isKeyWindow) }
                ?? UIWindow()
        }
    }
}
