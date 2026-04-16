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
