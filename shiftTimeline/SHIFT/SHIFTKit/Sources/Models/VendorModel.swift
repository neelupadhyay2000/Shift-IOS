import Foundation
import SwiftData

@Model
public final class VendorModel {
    public var id: UUID
    public var name: String
    public var role: VendorRole
    public var phone: String
    public var email: String
    public var notificationThreshold: TimeInterval
    public var hasAcknowledgedLatestShift: Bool
    public var event: EventModel?

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
