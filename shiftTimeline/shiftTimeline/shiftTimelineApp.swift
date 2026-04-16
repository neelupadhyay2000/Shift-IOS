//
//  shiftTimelineApp.swift
//  shiftTimeline
//
//  Created by Neel Upadhyay on 2026-04-07.
//

import SwiftUI
import SwiftData
import Services

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
