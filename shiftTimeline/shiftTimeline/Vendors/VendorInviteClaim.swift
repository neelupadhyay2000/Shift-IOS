import Foundation

/// The signed-in identity attempting to claim invites — the Supabase profile id
/// plus the phone/email it authenticated with (Apple or phone OTP).
nonisolated struct VendorInviteClaimIdentity: Equatable {
    let profileID: UUID
    let phone: String?
    let email: String?
}

/// Decides whether a signed-in identity may claim a given `event_vendors` invite
/// — the Supabase analog of the old `cloudKitRecordName` reconciler.
///
/// An invite is locked to the phone/email the planner addressed it to, so a claim
/// only matches when the signed-in identity owns that same contact:
/// - **email** — trimmed, case-insensitive equality;
/// - **phone** — equality after normalizing both sides to E.164 via the same
///   `PhoneAuthService.normalizePhone` the OTP sign-in uses, so a formatted local
///   number the planner typed matches the canonical number Supabase signed in.
///
/// This rule is the client-side spec for the matching the security-definer claim
/// RPC enforces server-side.
nonisolated enum VendorInviteClaim {

    /// `true` when `identity` owns the contact this invite is locked to.
    static func matches(
        invitedPhone: String?,
        invitedEmail: String?,
        identityPhone: String?,
        identityEmail: String?
    ) -> Bool {
        if let invitedEmail, let identityEmail,
           emailsMatch(invitedEmail, identityEmail) {
            return true
        }
        if let invitedPhone, let identityPhone,
           phonesMatch(invitedPhone, identityPhone) {
            return true
        }
        return false
    }

    private static func emailsMatch(_ lhs: String, _ rhs: String) -> Bool {
        let a = lhs.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let b = rhs.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !a.isEmpty && a == b
    }

    private static func phonesMatch(_ lhs: String, _ rhs: String) -> Bool {
        let a = PhoneAuthService.normalizePhone(lhs)
        let b = PhoneAuthService.normalizePhone(rhs)
        return PhoneAuthService.isValidE164(a) && a == b
    }
}
