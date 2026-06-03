import Foundation
import SwiftData

@Model
public final class VendorModel {
    public var id: UUID = UUID()
    public var name: String = ""
    public var role: VendorRole = VendorRole.custom
    public var phone: String = ""
    public var email: String = ""
    public var notificationThreshold: TimeInterval = 600
    public var hasAcknowledgedLatestShift: Bool = false
    /// Non-nil when the planner has determined that a shift exceeded this
    /// vendor's threshold and a visible notification is warranted.
    /// The vendor's device reads this after CloudKit sync and posts a local
    /// notification, then clears it.
    public var pendingShiftDelta: TimeInterval?
    /// The identity record name of the iCloud account linked to this vendor.
    /// Drives the invite-status chip (notInvited / invited / accepted) and
    /// block-detail visibility. Will be replaced by a Supabase user ID in E14.
    public var cloudKitRecordName: String?
    /// When a share invite was last sent to this vendor.
    /// Combined with `cloudKitRecordName`, drives the invite-status chip.
    /// `nil` for contact-only vendors that were never invited.
    public var invitedAt: Date?
    public var event: EventModel?

    @Relationship(deleteRule: .nullify)
    public var assignedBlocks: [TimeBlockModel]?

    public init(
        id: UUID = UUID(),
        name: String,
        role: VendorRole,
        phone: String = "",
        email: String = "",
        notificationThreshold: TimeInterval = 600,
        hasAcknowledgedLatestShift: Bool = false
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.phone = phone
        self.email = email
        self.notificationThreshold = notificationThreshold
        self.hasAcknowledgedLatestShift = hasAcknowledgedLatestShift
    }
}
