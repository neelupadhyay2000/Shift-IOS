//
//  shiftTimelineWatchApp.swift
//  shiftTimelineWatch Watch App
//
//  Created by Neel Upadhyay on 2026-04-07.
//

import SwiftUI
import Models

@main
struct shiftTimelineWatch_Watch_AppApp: App {

    @State private var sessionManager = WatchSessionManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(sessionManager)
                .onOpenURL { url in
                    // Handle shift://live/{eventID} from Watch complications.
                    // The Watch app currently shows a single live event, so
                    // the URL primarily confirms the app should foreground.
                    guard url.scheme == "shift" else { return }
                    // Future: use eventID to switch between multiple events.
                }
                .task {
                    sessionManager.activate()
                }
        }
    }
}
