import Foundation

/// A required account field that can be missing after sign-in.
enum ProfileField: String, CaseIterable, Sendable {
    case name
    case email
    case phone
}

// MARK: - Identifier uniqueness

/// Result of `identifier_status`: whether an email/phone is already in use, and
/// whether by the caller's own account (so the Edit screen doesn't self-collide).
nonisolated struct IdentifierStatus: Decodable, Equatable, Sendable {
    let emailInUse: Bool
    let phoneInUse: Bool
    let emailIsMine: Bool
    let phoneIsMine: Bool
    /// A verified GoTrue login for this identifier, as opposed to a value merely
    /// stored on some account's `profiles` row.
    let emailIsAuth: Bool
    let phoneIsAuth: Bool

    static let free = IdentifierStatus(
        emailInUse: false, phoneInUse: false,
        emailIsMine: false, phoneIsMine: false,
        emailIsAuth: false, phoneIsAuth: false
    )

    enum CodingKeys: String, CodingKey {
        case emailInUse = "email_in_use"
        case phoneInUse = "phone_in_use"
        case emailIsMine = "email_is_mine"
        case phoneIsMine = "phone_is_mine"
        case emailIsAuth = "email_is_auth"
        case phoneIsAuth = "phone_is_auth"
    }

    /// Taken by *someone else* — the signal that blocks completing a profile or an
    /// edit. The caller's own credential (`*_is_mine`) is not a collision.
    var emailTakenByOther: Bool { emailInUse && !emailIsMine }
    var phoneTakenByOther: Bool { phoneInUse && !phoneIsMine }

    /// At signup entry, an identifier should block the OTP only when it is used
    /// *solely* as another account's stored second credential — there is no login
    /// to reach it by, so creating a new account would duplicate it. A verified
    /// login (`is_auth`) must be allowed through: that's a returning user signing
    /// in. A free identifier is a new signup.
    var emailBlocksSignup: Bool { emailInUse && !emailIsAuth }
    var phoneBlocksSignup: Bool { phoneInUse && !phoneIsAuth }
}

/// Encodes the `identifier_status` RPC arguments. `encodeIfPresent` so a nil
/// identifier is omitted and the SQL default (null → not checked) applies.
nonisolated struct IdentifierStatusParams: Encodable, Sendable {
    let email: String?
    let phone: String?

    enum CodingKeys: String, CodingKey {
        case email = "p_email"
        case phone = "p_phone"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(email, forKey: .email)
        try container.encodeIfPresent(phone, forKey: .phone)
    }
}

/// Pure helpers for deriving the displayed identity. Lives in `Auth/` because
/// `SupabaseAuthService` depends on `nonEmpty` to strip the empty strings GoTrue
/// serializes for absent identity fields; the display helpers are extended onto it
/// in `Settings/AccountView.swift`.
enum AccountIdentity {
    /// Trimmed, or nil when the value is absent or blank.
    ///
    /// GoTrue reports a phone-only user's `email` as `""` and an email-only user's
    /// `phone` likewise — never nil. Treating blank as absent is what keeps a
    /// session refresh from writing those empty strings over the real values in
    /// `profiles`.
    static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

/// Surfaced by the completion flow so a misconfigured save shows a message
/// rather than silently doing nothing.
enum ProfileCompletionError: LocalizedError, Equatable {
    case notSignedIn
    /// The email entered already belongs to a different account.
    case emailInUse
    /// The phone entered already belongs to a different account.
    case phoneInUse

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            String(localized: "You're not signed in. Please try again.")
        case .emailInUse:
            String(localized: "That email is already part of another account. Sign in with it instead.")
        case .phoneInUse:
            String(localized: "That phone number is already part of another account. Sign in with it instead.")
        }
    }
}

/// Failures from the Edit Account screen. Email and phone are sign-in credentials,
/// so their edits go through GoTrue's verified change flow rather than a plain
/// `profiles` write — these are the ways that can be refused before a code is even
/// sent.
enum AccountIdentityError: LocalizedError, Equatable {
    case notSignedIn
    case blankName
    case invalidEmail
    case invalidPhone
    /// The submitted value already is the account's credential. Sending a code for
    /// a no-op change would be confusing and burns a rate-limit slot.
    case unchanged
    /// The email/phone belongs to a different account.
    case emailInUse
    case phoneInUse

    var errorDescription: String? {
        switch self {
        case .notSignedIn: String(localized: "You're not signed in. Please try again.")
        case .blankName: String(localized: "Your name can't be empty.")
        case .invalidEmail: String(localized: "Enter a valid email address.")
        case .invalidPhone: String(localized: "Enter a valid phone number, including the country code.")
        case .unchanged: String(localized: "That's already your current one.")
        case .emailInUse: String(localized: "That email is already part of another account.")
        case .phoneInUse: String(localized: "That phone number is already part of another account.")
        }
    }
}

/// The product rule for a "complete" account (updated 2026-07-10):
///
/// - **name** — required for every account.
/// - **email** — required for every account.
/// - **phone** — now ALSO required for every account. One person, one account, and
///   uniqueness is enforced across both channels — so both must be present. Email
///   signups add a phone; phone signups add an email. Existing single-credential
///   accounts are carried through the completion gate on their next launch.
///
/// Pure and synchronous — drives both the onboarding forms and the
/// "complete your profile" gate, and is fully unit-tested.
enum ProfileCompleteness {

    /// The required fields that are still missing or invalid.
    static func missingFields(name: String?, email: String?, phone: String?) -> Set<ProfileField> {
        var missing: Set<ProfileField> = []

        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedName.isEmpty {
            missing.insert(.name)
        }

        let trimmedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !EmailAuthService.isValidEmail(trimmedEmail) {
            missing.insert(.email)
        }

        let trimmedPhone = phone?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !PhoneAuthService.isValidE164(PhoneAuthService.normalizePhone(trimmedPhone)) {
            missing.insert(.phone)
        }

        return missing
    }

    /// `true` when the account has a name, a valid email, and a valid phone.
    static func isComplete(name: String?, email: String?, phone: String?) -> Bool {
        missingFields(name: name, email: email, phone: phone).isEmpty
    }
}
