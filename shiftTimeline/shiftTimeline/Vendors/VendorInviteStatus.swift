import Foundation

/// Where a vendor stands in the invite → accept lifecycle. Derived purely from
/// the two stored fields so the UI never has to hit CloudKit to render status.
///
/// - `accepted`: the vendor's iCloud identity has been linked
///   (`cloudKitRecordName` stamped by `VendorParticipantReconciler`).
/// - `invited`: a locked CKShare invite was sent (`invitedAt`) but not yet claimed.
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
