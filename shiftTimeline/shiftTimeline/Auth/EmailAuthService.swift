import Foundation
import Supabase

// MARK: - Error

enum EmailAuthError: LocalizedError, Sendable {
    case invalidEmail
    case invalidOTPToken
    /// `AuthResponse` came back without a session — defensive; email OTP
    /// verification yields a session on success.
    case sessionMissing

    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            String(localized: "Please enter a valid email address.")
        case .invalidOTPToken:
            String(localized: "Please enter the 6-digit code.")
        case .sessionMissing:
            String(localized: "Sign-in failed. Please try again.")
        }
    }
}

// MARK: - Service

/// Manages the Supabase email-OTP authentication flow — the email sibling of
/// ``PhoneAuthService``.
///
/// `requestOTP(email:)` asks Supabase to email a 6-digit code; `verifyOTP(email:token:)`
/// exchanges it for a session. Unlike phone OTP this needs no SMS provider —
/// Supabase's built-in email sends it — but the **Magic Link** email template must
/// be set to send the token (`{{ .Token }}`) rather than a link (see
/// `FeatureFlags.emailSignIn`).
///
/// Email is normalized (trimmed + lowercased) so it matches the case-insensitive
/// invite-claim rule in `claim_invite()`.
@MainActor
final class EmailAuthService {

    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    // MARK: - OTP Request

    /// Validates `email`, then asks Supabase to email a one-time code. Creates the
    /// user if they don't exist yet (default behaviour) so a first-time vendor can
    /// onboard from an invite.
    func requestOTP(email: String) async throws {
        let normalized = Self.normalizeEmail(email)
        guard Self.isValidEmail(normalized) else {
            throw EmailAuthError.invalidEmail
        }
        try await client.auth.signInWithOTP(email: normalized)
    }

    // MARK: - OTP Verification

    /// Exchanges `token` for a Supabase `Session`. Validates the token locally
    /// (6 digits) before the network call.
    @discardableResult
    func verifyOTP(email: String, token: String) async throws -> Session {
        guard Self.isValidOTPToken(token) else {
            throw EmailAuthError.invalidOTPToken
        }
        let response = try await client.auth.verifyOTP(
            email: Self.normalizeEmail(email),
            token: token,
            type: .email
        )
        guard let session = response.session else {
            throw EmailAuthError.sessionMissing
        }
        return session
    }

    /// Re-sends a code to `email`. Identical to `requestOTP` — Supabase invalidates
    /// the previous code and issues a fresh one — but named for call-site clarity.
    func resendOTP(email: String) async throws {
        try await requestOTP(email: email)
    }

    // MARK: - Validation

    /// Returns `true` when `token` is exactly 6 decimal digits.
    nonisolated static func isValidOTPToken(_ token: String) -> Bool {
        token.count == 6 && token.allSatisfy(\.isNumber)
    }

    /// Trims surrounding whitespace and lowercases, matching the server-side
    /// `claim_invite()` comparison (`lower(btrim(...))`).
    nonisolated static func normalizeEmail(_ input: String) -> String {
        input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Pragmatic `local@domain.tld` check — enough to gate the Send button and
    /// avoid an obviously-doomed network call; Supabase is the real authority.
    nonisolated static func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$"#
        return email.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
