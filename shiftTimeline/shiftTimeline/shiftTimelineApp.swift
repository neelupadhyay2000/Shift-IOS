//
//  shiftTimelineApp.swift
//  shiftTimeline
//
//  Created by Neel Upadhyay on 2026-04-07.
//

import SwiftUI
import SwiftData
import CloudKit
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

    var body: some Scene {
        WindowGroup {
            RootNavigator()
                .environment(watchSessionManager)
                .task {
                    watchSessionManager.activate()
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

// MARK: - CloudKit Share Acceptance

/// Handles incoming CKShare invitations when a vendor taps a share link.
///
/// `NSPersistentCloudKitContainer` (which backs SwiftData) automatically
/// mirrors the accepted share's records into the local store once
/// `CKAcceptSharesOperation` succeeds.
final class AppDelegate: NSObject, UIApplicationDelegate {

    private static let logger = Logger(
        subsystem: "com.neelsoftwaresolutions.shiftTimeline",
        category: "CloudSharing"
    )

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
