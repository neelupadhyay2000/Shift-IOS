import Foundation
import os
import SwiftData
import Models
import ObjCException

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

        // First attempt: open with the full migration plan. This can fail two ways:
        //   (a) A plain Swift error from `ModelContainer.init` — caught by `catch`.
        //   (b) An Objective-C `NSException` thrown from
        //       `NSLightweightMigrationStage initWithVersionChecksums:` when the
        //       on-disk store's schema checksum doesn't line up with any version
        //       in `SHIFTMigrationPlan`. Swift can't catch NSExceptions directly,
        //       so `tryBuildContainer` wraps the init in an ObjC `@try/@catch` shim.
        //
        // On failure we delete the local store and retry with several
        // progressively more aggressive fallbacks so the app always launches.
        if let built = Self.tryBuildContainer(
            schema: schema,
            configuration: config,
            migrationPlan: SHIFTMigrationPlan.self,
            label: "existing store with migration plan"
        ) {
            container = built
            return
        }

        Self.logger.error("Initial ModelContainer init failed — deleting store and retrying")
        Self.deleteStoreFiles(at: url)

        // Retry #1: fresh store on disk, no migration plan (nothing to migrate from).
        // CloudKit will re-hydrate user data after the container comes up.
        if let built = Self.tryBuildContainer(
            schema: schema,
            configuration: config,
            migrationPlan: nil,
            label: "fresh store without migration plan"
        ) {
            container = built
            return
        }

        // Retry #2: fresh store with migration plan, in case SwiftData requires it
        // to register schema identity with CloudKit mirroring.
        if let built = Self.tryBuildContainer(
            schema: schema,
            configuration: config,
            migrationPlan: SHIFTMigrationPlan.self,
            label: "fresh store with migration plan"
        ) {
            container = built
            return
        }

        // Retry #3: disable CloudKit mirroring entirely — local-only store.
        // Data will come back when the user relaunches after the next update,
        // but at least the app launches instead of aborting on startup.
        Self.deleteStoreFiles(at: url)
        let localOnly = ModelConfiguration(
            schema: schema,
            url: url,
            cloudKitDatabase: .none
        )
        if let built = Self.tryBuildContainer(
            schema: schema,
            configuration: localOnly,
            migrationPlan: nil,
            label: "fresh store local-only (CloudKit disabled)"
        ) {
            container = built
            return
        }

        // Last-resort: in-memory container. User data will not persist across
        // launches, but the app will not crash on launch.
        Self.logger.error("All on-disk ModelContainer attempts failed — using in-memory container as last resort")
        let memoryConfig = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        if let built = Self.tryBuildContainer(
            schema: schema,
            configuration: memoryConfig,
            migrationPlan: nil,
            label: "in-memory fallback"
        ) {
            container = built
            return
        }

        fatalError("Could not create any ModelContainer, even in-memory")
    }

    /// Attempts to build a `ModelContainer` while converting any Obj-C
    /// `NSException` (e.g. from `NSLightweightMigrationStage`) into a
    /// recoverable error. Returns `nil` on failure of either kind.
    private static func tryBuildContainer(
        schema: Schema,
        configuration: ModelConfiguration,
        migrationPlan: (any SchemaMigrationPlan.Type)?,
        label: String
    ) -> ModelContainer? {
        var built: ModelContainer?
        var swiftError: Error?
        var objcError: NSError?
        let succeeded = SHIFTTryBlock({
            do {
                if let migrationPlan {
                    built = try ModelContainer(
                        for: schema,
                        migrationPlan: migrationPlan,
                        configurations: [configuration]
                    )
                } else {
                    built = try ModelContainer(
                        for: schema,
                        configurations: [configuration]
                    )
                }
            } catch {
                swiftError = error
            }
        }, &objcError)

        if succeeded, let built, swiftError == nil {
            logger.info("ModelContainer built via: \(label)")
            return built
        }

        if let swiftError {
            logger.error("ModelContainer attempt '\(label)' failed: \(swiftError.localizedDescription)")
        } else if let objcError {
            logger.error("ModelContainer attempt '\(label)' threw NSException: \(objcError.localizedDescription)")
        } else {
            logger.error("ModelContainer attempt '\(label)' failed with unknown error")
        }
        return nil
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
