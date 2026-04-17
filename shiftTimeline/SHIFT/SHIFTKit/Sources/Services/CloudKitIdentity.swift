import CloudKit
import Foundation
import os

/// Fetches and caches the current iCloud user's record name in UserDefaults.
///
/// Views use `CloudKitIdentity.currentUserRecordName` to compare against
/// `EventModel.ownerRecordName` — a mismatch means the event was shared
/// by another user and should be treated as read-only.
public enum CloudKitIdentity {

    private static let key = "com.shift.currentUserRecordName"
    private static let logger = Logger(subsystem: "com.shift.cloudkit", category: "Identity")

    /// The cached CKRecord name for the signed-in iCloud user, or `nil`
    /// if not yet fetched or iCloud is unavailable.
    public static var currentUserRecordName: String? {
        UserDefaults.standard.string(forKey: key)
    }

    /// Fetches the current user's CKRecord ID and caches the record name.
    /// Call once at app launch (e.g. in a `.task` modifier).
    public static func fetchAndCache() async {
        let container = CKContainer(identifier: "iCloud.com.neelsoftwaresolutions.shiftTimeline")
        do {
            let recordID = try await container.userRecordID()
            UserDefaults.standard.set(recordID.recordName, forKey: key)
            logger.info("Cached CloudKit user record name")
        } catch {
            logger.debug("Could not fetch CloudKit user record ID: \(error.localizedDescription)")
        }
    }
}
