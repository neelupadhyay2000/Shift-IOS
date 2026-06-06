import Foundation
import Models
import Services

/// Errors raised while inviting a vendor.
nonisolated enum VendorInviteError: Error, Equatable {
    /// The vendor has neither a phone number nor an email, so there is no
    /// identity to lock the invite to (a contact-only vendor can't be invited).
    case notInvitable
}

/// Stamps the invite state onto a vendor's `event_vendors` row (SHIFT-625).
///
/// Inviting records `invitedAt` and persists the row through the vendor
/// repository, so the synced `event_vendors` row carries the invite fields —
/// `invited_phone` / `invited_email`, `role`, `notification_threshold`,
/// `invited_at` — with `profile_id` left null until the invitee claims the invite
/// on sign-in (SHIFT-621). The contact, role, and threshold fields are already on
/// the model from the vendor form; this only adds the invite timestamp.
///
/// Delivering the invite link (phone-first iMessage / email composer + deep link +
/// app-store fallback) is layered on top of the returned lookup (SHIFT-626).
@MainActor
struct VendorInviteService {

    private let repository: any VendorRepositing
    private let now: () -> Date

    init(repository: any VendorRepositing, now: @escaping () -> Date = { Date() }) {
        self.repository = repository
        self.now = now
    }

    /// Marks `vendor` as invited and persists the change.
    ///
    /// - Returns: the phone-first contact lookup the invite should be delivered
    ///   to (consumed by SHIFT-626's composer).
    /// - Throws: `VendorInviteError.notInvitable` when the vendor is contact-only
    ///   (no phone and no email); the row is left untouched and unsaved.
    @discardableResult
    func markInvited(_ vendor: VendorModel) async throws -> VendorInviteLookup {
        guard let lookup = VendorInviteEligibility.preferredLookup(
            phone: vendor.phone,
            email: vendor.email
        ) else {
            throw VendorInviteError.notInvitable
        }
        vendor.invitedAt = now()
        try await repository.save()
        return lookup
    }
}
