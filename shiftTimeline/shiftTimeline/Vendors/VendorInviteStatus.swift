import Foundation

/// Where a vendor stands in the invite → accept lifecycle. Derived purely from
/// two stored model fields so the UI never has to hit a remote service to render.
///
/// - `accepted`: the vendor's identity record has been linked (`cloudKitRecordName` set).
/// - `invited`: an invite was sent (`invitedAt`) but not yet claimed.
/// - `notInvited`: never invited (or a contact-only vendor).
nonisolated enum VendorInviteStatus: String {
    case notInvited
    case invited
    case accepted

    static func of(invitedAt: Date?, cloudKitRecordName: String?) -> VendorInviteStatus {
        if let recordName = cloudKitRecordName, !recordName.isEmpty {
            return .accepted
        }
        if invitedAt != nil {
            return .invited
        }
        return .notInvited
    }
}
