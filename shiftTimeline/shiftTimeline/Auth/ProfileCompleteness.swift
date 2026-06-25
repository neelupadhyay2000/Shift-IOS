import Foundation

/// A required account field that can be missing after sign-in.
enum ProfileField: String, CaseIterable, Sendable {
    case name
    case email
}

/// Surfaced by the completion flow so a misconfigured save shows a message
/// rather than silently doing nothing.
enum ProfileCompletionError: LocalizedError {
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .notSignedIn: String(localized: "You're not signed in. Please try again.")
        }
    }
}

/// The product rule for a "complete" account (2026-06-25):
///
/// - **name** — required for every account.
/// - **email** — required for every account: email-signups have it from the
///   start; phone-signups must add one (correlation handle for tracking).
/// - **phone** — only carried by phone-signups and never required of an email
///   user, so it is intentionally NOT gated here.
///
/// Pure and synchronous — drives both the onboarding forms and the
/// "complete your profile" gate, and is fully unit-tested.
enum ProfileCompleteness {

    /// The required fields that are still missing or invalid.
    static func missingFields(name: String?, email: String?) -> Set<ProfileField> {
        var missing: Set<ProfileField> = []

        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedName.isEmpty {
            missing.insert(.name)
        }

        let trimmedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !EmailAuthService.isValidEmail(trimmedEmail) {
            missing.insert(.email)
        }

        return missing
    }

    /// `true` when the account has a name and a valid email.
    static func isComplete(name: String?, email: String?) -> Bool {
        missingFields(name: name, email: email).isEmpty
    }
}
