//
//  shiftTimelineApp.swift
//  shiftTimeline
//
//  Created by Neel Upadhyay on 2026-04-07.
//

import SwiftUI
import SwiftData
import CloudKit
import Models
import Services
import os

/// SHIFT app entry point.
///
/// `PersistenceController.shared.container` registers all five SwiftData models:
///   - EventModel
///   - TimelineTrack
///   - TimeBlockModel
///   - VendorModel
///   - ShiftRecord
///
/// The container is injected into the SwiftUI environment here so every
/// descendant view can use `@Query` and `@Environment(\.modelContext)` without
/// additional setup.
@main
struct shiftTimelineApp: App {

    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var watchSessionManager = WatchSessionManager()

    init() {
        SunsetPrefetchTask.register()
        SunsetPrefetchTask.scheduleNextRefresh()
    }

    private static let logger = Logger(subsystem: "com.shift.app", category: "Lifecycle")

    /// One-time migration: stamps existing events with the current user's
    /// CloudKit record name so the shared-event detection works for
    /// events created before `ownerRecordName` was introduced.
    @MainActor
    private func backfillOwnerRecordNames() {
        guard let recordName = CloudKitIdentity.shared.currentUserRecordName else { return }
        let context = PersistenceController.shared.container.mainContext
        let descriptor = FetchDescriptor<EventModel>(
            predicate: #Predicate<EventModel> { $0.ownerRecordName == nil }
        )
        do {
            let events = try context.fetch(descriptor)
            guard !events.isEmpty else { return }
            for event in events {
                event.ownerRecordName = recordName
            }
            try context.save()
            Self.logger.info("Backfilled ownerRecordName for \(events.count) events")
        } catch {
            Self.logger.error("Failed to backfill ownerRecordNames: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootNavigator()
                .environment(watchSessionManager)
                .task {
                    watchSessionManager.activate()
                    await CloudKitIdentity.shared.fetchAndCache()
                    backfillOwnerRecordNames()
                    await SharedZoneSubscriptionManager.shared.registerIfNeeded()
                }
        }
        .modelContainer(PersistenceController.shared.container)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                SunsetPrefetchTask.scheduleNextRefresh()
            }
        }
    }
}

// MARK: - CloudKit Share Acceptance & Silent Push

/// Handles:
/// 1. Incoming CKShare invitations when a vendor taps a share link.
/// 2. Remote notification registration for silent-push-based sync.
/// 3. Silent push handling — triggers shared-zone change fetch so the
///    vendor's local SwiftData store stays current after planner edits.
final class AppDelegate: NSObject, UIApplicationDelegate {

    private static let logger = Logger(
        subsystem: "com.neelsoftwaresolutions.shiftTimeline",
        category: "CloudSharing"
    )

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Self.logger.info("Registered for remote notifications")
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Self.logger.error("Failed to register for remote notifications: \(error.localizedDescription)")
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // CloudKit silent push — fetch shared-zone changes.
        let notification = CKNotification(fromRemoteNotificationDictionary: userInfo)
        guard notification?.subscriptionID == "shared-zone-changes" else {
            completionHandler(.noData)
            return
        }

        Task {
            let hasNewData = await SharedZoneSubscriptionManager.shared.fetchChanges()
            completionHandler(hasNewData ? .newData : .noData)
        }
    }

    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        let container = CKContainer(identifier: cloudKitShareMetadata.containerIdentifier)

        let operation = CKAcceptSharesOperation(shareMetadatas: [cloudKitShareMetadata])
        operation.perShareResultBlock = { _, result in
            switch result {
            case .success:
                Self.logger.info("Successfully accepted CloudKit share")
            case .failure(let error):
                Self.logger.error("Failed to accept share: \(error.localizedDescription)")
            }
        }
        operation.qualityOfService = .userInteractive
        container.add(operation)
    }
}
