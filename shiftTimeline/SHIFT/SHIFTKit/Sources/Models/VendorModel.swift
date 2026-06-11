import Foundation
import SwiftData

@Model
public final class VendorModel {
    public var id: UUID = UUID()
    public var name: String = ""
    public var role: VendorRole = VendorRole.custom
    /// User-entered vendor type shown when `role == .custom` (e.g. "Videographer").
    /// Empty for built-in roles. Syncs through the `event_vendors.role` string
    /// column — see `VendorModel+SupabaseMapping`.
    public var customRoleLabel: String = ""
    public var phone: String = ""
    public var email: String = ""
    public var notificationThreshold: TimeInterval = 600
    public var hasAcknowledgedLatestShift: Bool = false
    /// Non-nil when a shift exceeded this vendor's threshold and a notification
    /// is warranted. Cleared when the vendor acknowledges.
    public var pendingShiftDelta: TimeInterval?
    /// When a share invite was last sent to this vendor.
    /// Drives the invite-status chip (notInvited / invited / accepted).
    /// `nil` for contact-only vendors that were never invited.
    public var invitedAt: Date?
    /// The Supabase profile (`event_vendors.profile_id` = `auth.uid()`) that
    /// claimed this invite, or `nil` for a contact-only / not-yet-claimed vendor.
    /// Set on claim-on-sign-in; a non-nil value flips the invite
    /// status to `accepted`.
    public var profileId: UUID?
    /// When the invite was claimed (`event_vendors.accepted_at`); `nil` until then.
    public var acceptedAt: Date?
    public var event: EventModel?

    /// Server `updated_at` of the last remote version applied to this row — the
    /// basis for last-write-wins conflict resolution (see `EventModel.updatedAt`).
    public var updatedAt: Date?

    @Relationship(deleteRule: .nullify)
    public var assignedBlocks: [TimeBlockModel]?

    public init(
        id: UUID = UUID(),
        name: String,
        role: VendorRole,
        customRoleLabel: String = "",
        phone: String = "",
        email: String = "",
        notificationThreshold: TimeInterval = 600,
        hasAcknowledgedLatestShift: Bool = false
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.customRoleLabel = customRoleLabel
        self.phone = phone
        self.email = email
        self.notificationThreshold = notificationThreshold
        self.hasAcknowledgedLatestShift = hasAcknowledgedLatestShift
    }
}
