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

    /// Background task that polls for shared-zone changes at a fixed interval
    /// while the app is in the foreground. Cancelled on background transition.
    ///
    /// Marked `@ObservationIgnored` so the `@Observable` macro does not
    /// generate observation tracking for this implementation-detail property.
    @ObservationIgnored private var foregroundPollTask: Task<Void, Never>?

    // MARK: - Init

    private init() {}

    // MARK: - Foreground Heartbeat Polling

    /// Starts a repeating poll that calls `fetchChanges()` every `interval`
    /// while the app is in the foreground.
    ///
    /// Silent push notifications (`content-available: 1`) are throttled by iOS
    /// in low-power mode, during APNs coalescing, and when the app is backgrounded.
    /// This heartbeat ensures vendors receive planner updates within `interval`
    /// even when a push is dropped.
    ///
    /// Safe to call repeatedly — cancels any running poll before starting a new one.
    /// Always paired with `stopForegroundPolling()` on background transition.
    public func startForegroundPolling(interval: Duration = .seconds(30)) {
        foregroundPollTask?.cancel()
        foregroundPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                SyncDiagnosticsCenter.shared.record(.push, "pollTick")
                await self?.fetchChanges()
            }
        }
        Self.logger.info("Foreground polling started — interval: \(interval)")
    }

    /// Cancels the foreground poll started by `startForegroundPolling()`.
    /// Call this when the app transitions to `.background` or `.inactive`.
    public func stopForegroundPolling() {
        foregroundPollTask?.cancel()
        foregroundPollTask = nil
        Self.logger.info("Foreground polling stopped")
    }

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
                SyncDiagnosticsCenter.shared.record(.subscription, "alreadyRegistered")
                return
            } catch {
                // Subscription was purged — fall through to re-create.
                Self.logger.info("Subscription purged by CloudKit — re-registering")
                SyncDiagnosticsCenter.shared.record(.subscription, "purgedReRegistering", severity: .warning)
                UserDefaults.standard.set(false, forKey: Self.subscriptionSavedKey)
            }
        }

        await createSubscription()
    }

    /// Forces a fresh subscription registration, bypassing the "already saved"
    /// short-circuit. Used by the diagnostics screen to test whether the
    /// silent-push subscription is the broken link.
    public func forceReRegister() async {
        UserDefaults.standard.set(false, forKey: Self.subscriptionSavedKey)
        isSubscribed = false
        SyncDiagnosticsCenter.shared.record(.subscription, "forceReRegister")
        await createSubscription()
    }

    /// Clears the cached server + per-zone change tokens so the next fetch
    /// re-reads every record from scratch. Tests the "stale change token"
    /// hypothesis (vendor sees `databaseChanges` return 0 zones forever).
    public func resetAllChangeTokens() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.serverChangeTokenKey)
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix(Self.zoneChangeTokenKeyPrefix) {
            defaults.removeObject(forKey: key)
        }
        SyncDiagnosticsCenter.shared.record(.fetch, "changeTokensReset", severity: .warning)
        Self.logger.info("Cleared all shared-DB change tokens")
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
            SyncDiagnosticsCenter.shared.record(.subscription, "created")
        } catch {
            Self.logger.error("Failed to create shared-zone subscription: \(error.localizedDescription)")
            SyncDiagnosticsCenter.shared.record(
                .subscription,
                "createFailed",
                params: ["error": error.localizedDescription],
                severity: .error
            )
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
        SyncDiagnosticsCenter.shared.record(.shareAccept, "targetedZoneFetchStarted", params: ["zone": zoneID.zoneName])
        clearZoneChangeToken(for: zoneID)
        do {
            try await fetchZoneChanges(in: [zoneID])
            Self.logger.info("Targeted zone fetch complete")
            SyncDiagnosticsCenter.shared.record(.shareAccept, "targetedZoneFetchComplete", params: ["zone": zoneID.zoneName])
        } catch {
            Self.logger.error("Targeted zone fetch failed: \(error.localizedDescription)")
            SyncDiagnosticsCenter.shared.record(
                .shareAccept,
                "targetedZoneFetchFailed",
                params: ["zone": zoneID.zoneName, "error": error.localizedDescription],
                severity: .error
            )
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
        SyncDiagnosticsCenter.shared.record(.fetch, "fetchChangesStarted")

        do {
            let (changedZoneIDs, purgedZoneIDs) = try await fetchDatabaseChanges()
            let hasWork = !changedZoneIDs.isEmpty || !purgedZoneIDs.isEmpty
            SyncDiagnosticsCenter.shared.record(
                .fetch,
                "databaseChanges",
                params: ["changedZones": "\(changedZoneIDs.count)", "purgedZones": "\(purgedZoneIDs.count)"],
                severity: hasWork ? .info : .info
            )
            guard hasWork else {
                Self.logger.info("No changed zones")
                return false
            }
            if !changedZoneIDs.isEmpty {
                try await fetchZoneChanges(in: changedZoneIDs)
            }
            if !purgedZoneIDs.isEmpty {
                await deletePurgedZoneEvents(purgedZoneIDs)
            }
            return true
        } catch {
            Self.logger.error("Failed to fetch shared changes: \(error.localizedDescription)")
            SyncDiagnosticsCenter.shared.record(
                .fetch,
                "fetchChangesFailed",
                params: ["error": error.localizedDescription],
                severity: .error
            )
            return false
        }
    }

    // MARK: - Database-Level Changes

    /// Fetches which zones have changed since the last server change token.
    /// Returns changed zones (need record-level fetch) AND purged zones
    /// (the planner deleted their data — vendor must remove the local event).
    private func fetchDatabaseChanges() async throws -> (changed: [CKRecordZone.ID], purged: [CKRecordZone.ID]) {
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

        // Clear tokens for deleted zones so a future fetch starts fresh.
        for zoneID in purgedZoneIDs {
            clearZoneChangeToken(for: zoneID)
        }

        if let currentToken {
            saveServerChangeToken(currentToken)
        }

        return (changed: changedZoneIDs, purged: purgedZoneIDs)
    }

    /// Deletes local events that were synced from zones the planner has since removed
    /// (i.e. the planner deleted the shared event and CloudKit purged the shared zone).
    ///
    /// `CKRecordZone.ID.ownerName` is the planner's iCloud record name — the same value
    /// stored in `EventModel.ownerRecordName`. Any vendor-side event whose owner matches
    /// a purged zone owner is now orphaned and must be removed.
    private func deletePurgedZoneEvents(_ purgedZoneIDs: [CKRecordZone.ID]) async {
        let ownerNames = purgedZoneIDs.map(\.ownerName)
        Self.logger.info("Purged zones for owners: \(ownerNames.joined(separator: ", "))")
        await MainActor.run {
            let context = PersistenceController.shared.container.mainContext
            let syncer = SharedRecordSyncer(context: context)
            do {
                try syncer.deletePurgedZoneEvents(ownerRecordNames: ownerNames)
            } catch {
                Self.logger.error("Failed to delete purged-zone events: \(error.localizedDescription)")
            }
        }
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
                SyncDiagnosticsCenter.shared.record(
                    .fetch,
                    "zoneRecordChanges",
                    params: [
                        "zone": zoneID.zoneName,
                        "modified": "\(changes.modificationResultsByID.count)",
                        "deleted": "\(changes.deletions.count)",
                    ]
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
