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
    /// Non-nil when a shift exceeded this vendor's threshold and a notification
    /// is warranted. Cleared when the vendor acknowledges.
    public var pendingShiftDelta: TimeInterval?
    /// When a share invite was last sent to this vendor.
    /// Drives the invite-status chip (notInvited / invited / accepted).
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
