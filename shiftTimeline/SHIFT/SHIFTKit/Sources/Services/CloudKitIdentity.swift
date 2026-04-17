import CloudKit
import Foundation
import os

/// Fetches and caches the current iCloud user's record name.
///
/// Published via `@Observable` so SwiftUI views that read
/// `shared.currentUserRecordName` re-render when the value changes
/// (e.g. after the async fetch completes at launch).
@Observable
public final class CloudKitIdentity: @unchecked Sendable {

    public static let shared = CloudKitIdentity()

    private static let key = "com.shift.currentUserRecordName"
    private static let logger = Logger(subsystem: "com.shift.cloudkit", category: "Identity")

    /// The CKRecord name for the signed-in iCloud user, or `nil`
    /// if not yet fetched or iCloud is unavailable.
    public private(set) var currentUserRecordName: String?

    private init() {
        currentUserRecordName = UserDefaults.standard.string(forKey: Self.key)
    }

    /// Fetches the current user's CKRecord ID and caches the record name.
    /// Call once at app launch (e.g. in a `.task` modifier).
    @MainActor
    public func fetchAndCache() async {
        let container = CKContainer(identifier: "iCloud.com.neelsoftwaresolutions.shiftTimeline")
        do {
            let recordID = try await container.userRecordID()
            let name = recordID.recordName
            UserDefaults.standard.set(name, forKey: Self.key)
            currentUserRecordName = name
            Self.logger.info("Cached CloudKit user record name")
        } catch {
            Self.logger.error("Could not fetch CloudKit user record ID: \(error.localizedDescription)")
        }
    }
}
