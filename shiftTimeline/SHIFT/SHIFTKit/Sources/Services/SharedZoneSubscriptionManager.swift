import CloudKit
import Foundation
import os

/// Manages a `CKDatabaseSubscription` on the shared CloudKit database so vendor devices
/// receive silent push notifications when the planner updates the timeline.
/// Subscription ID and server change token are persisted in UserDefaults.
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

    @ObservationIgnored private var foregroundPollTask: Task<Void, Never>?

    // MARK: - Init

    private init() {}

    // MARK: - Foreground Heartbeat Polling

    /// Starts a repeating poll every `interval`. Safe to call repeatedly — cancels any running poll first.
    public func startForegroundPolling(interval: Duration = .seconds(30)) {
        foregroundPollTask?.cancel()
        foregroundPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                await self?.fetchChanges()
            }
        }
        Self.logger.info("Foreground polling started — interval: \(interval)")
    }

    /// Cancels the foreground poll. Call on `.background` / `.inactive` transitions.
    public func stopForegroundPolling() {
        foregroundPollTask?.cancel()
        foregroundPollTask = nil
        Self.logger.info("Foreground polling stopped")
    }

    // MARK: - Subscription Registration

    /// Ensures the shared-database subscription exists. Safe to call repeatedly.
    public func registerIfNeeded() async {
        if UserDefaults.standard.bool(forKey: Self.subscriptionSavedKey) {
            // Verify it still exists on the server.
            do {
                _ = try await sharedDB.subscription(for: Self.subscriptionID)
                isSubscribed = true
                Self.logger.info("Shared-zone subscription already registered")
                return
            } catch {
                // Subscription purged — re-create.
                Self.logger.info("Subscription purged by CloudKit — re-registering")
                UserDefaults.standard.set(false, forKey: Self.subscriptionSavedKey)
            }
        }

        await createSubscription()
    }

    private func createSubscription() async {
        let subscription = CKDatabaseSubscription(subscriptionID: Self.subscriptionID)

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
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

    /// Performs a full fetch of all records in a specific shared zone.
    /// Use immediately after `CKAcceptSharesOperation` succeeds to bypass the brief
    /// propagation window before the zone appears in the change feed.
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

    /// Fetches changes from the shared database. Returns `true` if new data was fetched.
    @discardableResult
    public func fetchChanges() async -> Bool {
        Self.logger.info("Fetching shared-database changes")

        do {
            let (changedZoneIDs, purgedZoneIDs) = try await fetchDatabaseChanges()
            let hasWork = !changedZoneIDs.isEmpty || !purgedZoneIDs.isEmpty
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
            return false
        }
    }

    // MARK: - Database-Level Changes

    /// Fetches which zones changed since the last token. Returns changed zones and purged zones.
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

    /// Deletes local events whose zones the planner has removed.
    /// `CKRecordZone.ID.ownerName` maps to `EventModel.ownerRecordName`.
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

    /// Fetches record-level changes for the given zones and merges them into SwiftData via `SharedRecordSyncer`.
    /// `NSPersistentCloudKitContainer` only mirrors the private DB, so this bridges shared-zone records manually.
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
