import Foundation
import Supabase

// MARK: - Error

enum PhoneAuthError: LocalizedError, Sendable {
    case invalidPhoneNumber

    var errorDescription: String? {
        switch self {
        case .invalidPhoneNumber:
            String(localized: "Please enter a valid phone number.")
        }
    }
}

// MARK: - Service

/// Manages the Supabase phone-OTP authentication flow.
///
/// Call `requestOTP(phone:)` to send a code, then (in SHIFT-578) call
/// `verifyOTP(phone:token:)` to exchange the code for a session.
@MainActor
final class PhoneAuthService {

    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    // MARK: - OTP Request

    /// Normalizes `phone` to E.164, then asks Supabase to send an OTP SMS.
    ///
    /// Throws `PhoneAuthError.invalidPhoneNumber` when the number is
    /// unreachable after normalization. Supabase errors propagate as-is.
    func requestOTP(phone: String) async throws {
        let normalized = Self.normalizePhone(phone)
        guard Self.isValidE164(normalized) else {
            throw PhoneAuthError.invalidPhoneNumber
        }
        try await client.auth.signInWithOTP(phone: normalized)
    }

    // MARK: - Phone Normalization

    /// Normalizes a raw phone number string to E.164 format.
    ///
    /// Rules (applied in order):
    /// 1. If the input already has a `+` prefix, strip non-digit chars after it
    ///    and return — the caller is assumed to know their own country code.
    /// 2. Otherwise, strip all non-digit characters.
    /// 3. 10 digits → assume US, prepend `+1`.
    /// 4. 11 digits starting with `1` → assume US with country code, prepend `+`.
    /// 5. Anything else → prepend `+` and let `isValidE164` catch bad lengths.
    nonisolated static func normalizePhone(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("+") {
            let digits = String(trimmed.dropFirst().filter(\.isNumber))
            return "+\(digits)"
        }

        let digits = String(trimmed.filter(\.isNumber))

        switch digits.count {
        case 10:
            return "+1\(digits)"
        case 11 where digits.hasPrefix("1"):
            return "+\(digits)"
        default:
            return "+\(digits)"
        }
    }

    /// Returns `true` when `phone` satisfies the E.164 format:
    /// a `+` followed by 7–15 digits (no spaces, no punctuation).
    nonisolated static func isValidE164(_ phone: String) -> Bool {
        guard phone.hasPrefix("+") else { return false }
        let digits = phone.dropFirst()
        guard (7...15).contains(digits.count) else { return false }
        return digits.allSatisfy(\.isNumber)
    }
}
