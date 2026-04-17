import Foundation
import SwiftData

@Model
public final class VendorModel {
    public var id: UUID = UUID()
    public var name: String = ""
    public var role: VendorRole = VendorRole.custom
    public var phone: String = ""
    public var email: String = ""
    public var notificationThreshold: TimeInterval = 300
    public var hasAcknowledgedLatestShift: Bool = false
    /// The CloudKit user record name of the iCloud account that accepted the share
    /// for this vendor. Used to scope block details — vendors only see notes/details
    /// for blocks they are assigned to.
    public var cloudKitRecordName: String?
    public var event: EventModel?

    @Relationship(deleteRule: .nullify)
    public var assignedBlocks: [TimeBlockModel]?

    public init(
        id: UUID = UUID(),
        name: String,
        role: VendorRole,
        phone: String = "",
        email: String = "",
        notificationThreshold: TimeInterval = 300,
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
