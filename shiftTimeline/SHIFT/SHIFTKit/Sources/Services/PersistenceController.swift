import Foundation
import os
import SwiftData
import Models

public final class PersistenceController: Sendable {

    private static let logger = Logger(subsystem: "com.shift.persistence", category: "store")

    /// The CloudKit container identifier for iCloud sync.
    private static let cloudKitContainerID = "iCloud.com.neelsoftwaresolutions.shiftTimeline"

    /// The App Group identifier shared between the main app and extensions.
    private static let appGroupID = "group.com.neelsoftwaresolutions.shiftTimeline"

    public static let shared = PersistenceController()

    public let container: ModelContainer

    public static var schema: Schema {
        Schema([
            EventModel.self,
            TimeBlockModel.self,
            TimelineTrack.self,
            VendorModel.self,
            ShiftRecord.self,
        ])
    }

    /// Returns the store URL inside the shared App Group container,
    /// creating the parent directory if it doesn't exist.
    private static var storeURL: URL {
        guard let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            logger.warning("App Group container unavailable — falling back to default location")
            return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("default.store")
        }

        let supportDir = groupURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)

        if !FileManager.default.fileExists(atPath: supportDir.path) {
            do {
                try FileManager.default.createDirectory(
                    at: supportDir, withIntermediateDirectories: true
                )
            } catch {
                logger.error("Failed to create App Group support dir: \(error.localizedDescription) — falling back to default location")
                return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                    .appendingPathComponent("default.store")
            }
        }

        return supportDir.appendingPathComponent("default.store")
    }

    private init() {
        let schema = Self.schema
        let url = Self.storeURL
        let config = ModelConfiguration(
            schema: schema,
            url: url,
            cloudKitDatabase: .automatic
        )

        do {
            container = try ModelContainer(
                for: schema,
                configurations: [config]
            )
            Self.logger.info("ModelContainer created successfully")
        } catch {
            Self.logger.error("ModelContainer failed: \(error.localizedDescription) — deleting store and retrying")
            Self.deleteStoreFiles(at: url)
            do {
                container = try ModelContainer(
                    for: schema,
                    configurations: [config]
                )
            } catch {
                fatalError("Could not create ModelContainer after store reset: \(error)")
            }
        }
    }

    private static func deleteStoreFiles(at url: URL) {
        let relatedFiles = [
            url,
            url.deletingPathExtension().appendingPathExtension("store-shm"),
            url.deletingPathExtension().appendingPathExtension("store-wal"),
        ]
        for file in relatedFiles {
            try? FileManager.default.removeItem(at: file)
        }
    }

    public static func forTesting() throws -> ModelContainer {
        let schema = Self.schema
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [config])
    }
}
