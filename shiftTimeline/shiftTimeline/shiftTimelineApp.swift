//
//  shiftTimelineApp.swift
//  shiftTimeline
//
//  Created by Neel Upadhyay on 2026-04-07.
//

import SwiftUI
import SwiftData
import Services

@main
struct shiftTimelineApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(PersistenceController.shared.container)
    }
}
