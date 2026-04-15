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
                .onAppear {
                    sessionManager.activate()
                }
        }
    }
}
