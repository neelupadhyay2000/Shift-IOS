import Foundation

/// The identity used to invite a vendor as a locked CKShare participant.
nonisolated enum VendorInviteLookup: Equatable {
    case phone(String)
    case email(String)
}

/// Decides whether (and how) a vendor can be invited as an app collaborator.
///
/// Per product rule, **phone is preferred** over email for the invite (the
/// invite drafts an iMessage first). A vendor with neither is "contact-only":
/// they appear in the call list / PDF / block assignment but can't be invited
/// and won't receive notifications.
nonisolated enum VendorInviteEligibility {

    static func preferredLookup(phone: String, email: String) -> VendorInviteLookup? {
        let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPhone.isEmpty {
            return .phone(trimmedPhone)
        }
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedEmail.isEmpty {
            return .email(trimmedEmail)
        }
        return nil
    }
}
