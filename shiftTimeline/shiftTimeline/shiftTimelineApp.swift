//
//  shiftTimelineApp.swift
//  shiftTimeline
//
//  Created by Neel Upadhyay on 2026-04-07.
//

import SwiftUI
import SwiftData
import Models
import Engine
import Services

@main
struct shiftTimelineApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            EventModel.self,
            TimeBlockModel.self,
            TimelineTrack.self,
            VendorModel.self,
            ShiftRecord.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // During development, if the schema changed, delete the old store and retry
            let url = modelConfiguration.url
            let relatedFiles = [url, url.deletingPathExtension().appendingPathExtension("store-shm"), url.deletingPathExtension().appendingPathExtension("store-wal")]
            for file in relatedFiles {
                try? FileManager.default.removeItem(at: file)
            }
            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
