import CloudKit
import Foundation
import os

/// Manages a `CKDatabaseSubscription` on the shared CloudKit database so
/// vendor devices receive silent push notifications whenever the planner
/// shifts the timeline.
///
/// The subscription is created once and its ID is persisted in UserDefaults.
/// On each app launch, the manager checks whether CloudKit still knows about
/// the subscription and re-registers it if it was purged (e.g. by CloudKit
/// cleanup policies). A server change token is cached so that
/// `fetchChanges()` only pulls records modified since the last fetch.
@Observable
public final class SharedZoneSubscriptionManager: @unchecked Sendable {

    public static let shared = SharedZoneSubscriptionManager()

    // MARK: - Constants

    public static let subscriptionID = "shared-zone-changes"
    private static let subscriptionSavedKey = "com.shift.sharedZoneSubscriptionSaved"
    private static let serverChangeTokenKey = "com.shift.sharedDBServerChangeToken"
    private static let zoneChangeTokenKeyPrefix = "com.shift.sharedZoneChangeToken."

    private static let logger = Logger(
        subsystem: "com.shift.cloudkit",
        category: "SharedZoneSubscription"
    )

    private let container = CKContainer(
        identifier: "iCloud.com.neelsoftwaresolutions.shiftTimeline"
    )

    private var sharedDB: CKDatabase {
        container.sharedCloudDatabase
    }

    // MARK: - Public State

    /// `true` once the subscription has been confirmed with CloudKit.
    public private(set) var isSubscribed = false

    // MARK: - Init

    private init() {}

    // MARK: - Subscription Registration

    /// Ensures the shared-database subscription exists. Call once at launch.
    /// Safe to call repeatedly — skips the server round-trip if the
    /// subscription was already saved and has not been purged.
    public func registerIfNeeded() async {
        if UserDefaults.standard.bool(forKey: Self.subscriptionSavedKey) {
            // Verify it still exists on the server.
            do {
                _ = try await sharedDB.subscription(for: Self.subscriptionID)
                isSubscribed = true
                Self.logger.info("Shared-zone subscription already registered")
                return
            } catch {
                // Subscription was purged — fall through to re-create.
                Self.logger.info("Subscription purged by CloudKit — re-registering")
                UserDefaults.standard.set(false, forKey: Self.subscriptionSavedKey)
            }
        }

        await createSubscription()
    }

    private func createSubscription() async {
        let subscription = CKDatabaseSubscription(subscriptionID: Self.subscriptionID)

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true // silent push
        subscription.notificationInfo = notificationInfo

        do {
            _ = try await sharedDB.modifySubscriptions(saving: [subscription], deleting: [])
            UserDefaults.standard.set(true, forKey: Self.subscriptionSavedKey)
            isSubscribed = true
            Self.logger.info("Shared-zone subscription created")
        } catch {
            Self.logger.error("Failed to create shared-zone subscription: \(error.localizedDescription)")
        }
    }

    // MARK: - Change Fetching

    /// Performs an immediate full fetch of every record in a specific shared zone.
    ///
    /// Use this immediately after `CKAcceptSharesOperation` succeeds. It bypasses
    /// `fetchDatabaseChanges()` entirely — which can return an empty zone list in the
    /// brief window between share acceptance and CloudKit propagating the new zone into
    /// the change feed — and instead reads the specific zone we already know about from
    /// the share metadata.
    ///
    /// The caller supplies the zone ID from `shareMetadata.rootRecordID.zoneID`, which
    /// is the planner's `com.apple.coredata.cloudkit.zone`.
    public func fetchAllRecords(inZone zoneID: CKRecordZone.ID) async {
        Self.logger.info("Performing targeted zone fetch for accepted share: \(zoneID.zoneName)")
        clearZoneChangeToken(for: zoneID)
        do {
            try await fetchZoneChanges(in: [zoneID])
            Self.logger.info("Targeted zone fetch complete")
        } catch {
            Self.logger.error("Targeted zone fetch failed: \(error.localizedDescription)")
        }
    }

    /// Fetches changes from the shared database. Call this from
    /// `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`
    /// or whenever you want to pull the latest shared timeline data.
    ///
    /// Returns `true` if new data was fetched.
    @discardableResult
    public func fetchChanges() async -> Bool {
        Self.logger.info("Fetching shared-database changes")

        do {
            let changedZoneIDs = try await fetchDatabaseChanges()
            guard !changedZoneIDs.isEmpty else {
                Self.logger.info("No changed zones")
                return false
            }
            try await fetchZoneChanges(in: changedZoneIDs)
            return true
        } catch {
            Self.logger.error("Failed to fetch shared changes: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Database-Level Changes

    /// Fetches which zones have changed since the last server change token.
    private func fetchDatabaseChanges() async throws -> [CKRecordZone.ID] {
        var currentToken = loadServerChangeToken()

        var changedZoneIDs: [CKRecordZone.ID] = []
        var purgedZoneIDs: [CKRecordZone.ID] = []
        var moreComing = true

        while moreComing {
            let changes = try await sharedDB.databaseChanges(since: currentToken)
            let modifications = changes.modifications.map(\.zoneID)
            let deletions = changes.deletions.map(\.zoneID)
            changedZoneIDs.append(contentsOf: modifications)
            purgedZoneIDs.append(contentsOf: deletions)
            currentToken = changes.changeToken
            moreComing = changes.moreComing
        }

        // Clear tokens for deleted zones.
        for zoneID in purgedZoneIDs {
            clearZoneChangeToken(for: zoneID)
        }

        if let currentToken {
            saveServerChangeToken(currentToken)
        }

        return changedZoneIDs
    }

    // MARK: - Zone-Level Changes

    /// Fetches record-level changes for the given zones and merges them into
    /// the local SwiftData store via `SharedRecordSyncer`.
    ///
    /// `NSPersistentCloudKitContainer` only mirrors the private CloudKit database,
    /// so shared-zone records never reach SwiftData automatically. This method
    /// performs that bridging manually: every modified/deleted CKRecord is
    /// collected across all pages and all zones, then handed to `SharedRecordSyncer`
    /// on the main actor in one atomic merge.
    private func fetchZoneChanges(in zoneIDs: [CKRecordZone.ID]) async throws {
        var modified: [CKRecord] = []
        var deleted: [SharedDeletedRecord] = []

        for zoneID in zoneIDs {
            var currentToken = loadZoneChangeToken(for: zoneID)
            var moreComing = true

            while moreComing {
                let changes = try await sharedDB.recordZoneChanges(
                    inZoneWith: zoneID,
                    since: currentToken
                )

                Self.logger.info(
                    "Zone \(zoneID.zoneName): \(changes.modificationResultsByID.count) modified, \(changes.deletions.count) deleted"
                )

                for (_, result) in changes.modificationResultsByID {
                    if case .success(let modification) = result {
                        modified.append(modification.record)
                    }
                }

                for deletion in changes.deletions {
                    deleted.append(SharedDeletedRecord(
                        recordID: deletion.recordID,
                        recordType: deletion.recordType
                    ))
                }

                currentToken = changes.changeToken
                saveZoneChangeToken(changes.changeToken, for: zoneID)

                moreComing = changes.moreComing
            }
        }

        guard !modified.isEmpty || !deleted.isEmpty else { return }

        let capturedModified = modified
        let capturedDeleted = deleted
        await MainActor.run {
            let context = PersistenceController.shared.container.mainContext
            let syncer = SharedRecordSyncer(context: context)
            do {
                try syncer.merge(modified: capturedModified, deleted: capturedDeleted)
            } catch {
                Self.logger.error("SharedRecordSyncer failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Token Persistence

    private func loadServerChangeToken() -> CKServerChangeToken? {
        guard let data = UserDefaults.standard.data(forKey: Self.serverChangeTokenKey) else {
            return nil
        }
        return try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: CKServerChangeToken.self,
            from: data
        )
    }

    private func saveServerChangeToken(_ token: CKServerChangeToken) {
        guard let data = try? NSKeyedArchiver.archivedData(
            withRootObject: token,
            requiringSecureCoding: true
        ) else { return }
        UserDefaults.standard.set(data, forKey: Self.serverChangeTokenKey)
    }

    private func loadZoneChangeToken(for zoneID: CKRecordZone.ID) -> CKServerChangeToken? {
        let key = Self.zoneChangeTokenKeyPrefix + zoneID.zoneName
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return nil
        }
        return try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: CKServerChangeToken.self,
            from: data
        )
    }

    private func saveZoneChangeToken(_ token: CKServerChangeToken, for zoneID: CKRecordZone.ID) {
        let key = Self.zoneChangeTokenKeyPrefix + zoneID.zoneName
        guard let data = try? NSKeyedArchiver.archivedData(
            withRootObject: token,
            requiringSecureCoding: true
        ) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func clearZoneChangeToken(for zoneID: CKRecordZone.ID) {
        let key = Self.zoneChangeTokenKeyPrefix + zoneID.zoneName
        UserDefaults.standard.removeObject(forKey: key)
    }
}
