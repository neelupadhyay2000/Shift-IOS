import Foundation
import os
import SwiftData
import Models
import ObjCException

/// Manages the SwiftData `ModelContainer` with a CloudKit-backed store.
/// Uses last-write-wins conflict resolution (product decision — data is single-planner owned).
public final class PersistenceController: Sendable {

    private static let logger = Logger(subsystem: "com.shift.persistence", category: "store")

    /// The CloudKit container identifier for iCloud sync.
    private static let cloudKitContainerID = "iCloud.com.neelsoftwaresolutions.shiftTimeline"

    /// The App Group identifier shared between the main app and extensions.
    private static let appGroupID = "group.com.neelsoftwaresolutions.shiftTimeline"

    public static let shared = PersistenceController()

    public let container: ModelContainer

    /// Tri-state CloudKit mirror health. `.degraded` → show sync banner; `.disabled` → CloudKit off.
    public let cloudKitMirrorState: CloudKitMirrorState

    public static var schema: Schema {
        Schema([
            EventModel.self,
            TimeBlockModel.self,
            TimelineTrack.self,
            VendorModel.self,
            ShiftRecord.self,
        ])
    }

    /// Store URL inside the shared App Group container. Creates the directory if needed.
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

        // Attempt 1: existing store with full migration plan.
        if let built = Self.tryBuildContainer(
            schema: schema,
            configuration: config,
            migrationPlan: SHIFTMigrationPlan.self,
            label: "existing store with migration plan"
        ) {
            container = built
            cloudKitMirrorState = .from(attempt: .existingStoreWithPlan)
            return
        }

        // Attempt 2: delete corrupt store, retry with migration plan. CloudKit re-downloads data after sync.
        Self.logger.error("Initial ModelContainer init failed — deleting store and retrying with migration plan")
        Self.deleteStoreFiles(at: url)

        if let built = Self.tryBuildContainer(
            schema: schema,
            configuration: config,
            migrationPlan: SHIFTMigrationPlan.self,
            label: "fresh store with migration plan"
        ) {
            container = built
            cloudKitMirrorState = .from(attempt: .freshStoreWithPlan)
            return
        }

        // Attempt 3: fresh store without migration plan, CloudKit still enabled (may degrade).
        Self.logger.error("Migration plan failed on fresh store — retrying without migration plan")
        Self.deleteStoreFiles(at: url)

        if let built = Self.tryBuildContainer(
            schema: schema,
            configuration: config,
            migrationPlan: nil,
            label: "fresh store without migration plan (CloudKit still enabled)"
        ) {
            container = built
            cloudKitMirrorState = .from(attempt: .freshStoreWithoutPlan)
            Self.logger.error("CloudKit enabled WITHOUT migration plan — sync may be degraded")
            return
        }

        // Attempt 4: local-only store. App launches but CloudKit is disabled.
        Self.logger.fault("All CloudKit-enabled attempts failed — falling back to local-only store. CloudKit sync is DISABLED.")
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
            label: "local-only store (CloudKit DISABLED)"
        ) {
            container = built
            cloudKitMirrorState = .from(attempt: .localOnly)
            return
        }

        // Last resort: in-memory. Data won't persist across launches.
        Self.logger.fault("All on-disk attempts failed — using in-memory container")
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
            cloudKitMirrorState = .from(attempt: .inMemory)
            return
        }

        fatalError("Could not create any ModelContainer, even in-memory")
    }

    /// Builds a `ModelContainer`, converting Obj-C `NSException`s into recoverable errors. Returns `nil` on failure.
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

    /// Creates and inserts a `ShiftRecord` for a committed shift. Call before `context.save()` at every shift commit site.
    public static func recordShift(
        deltaMinutes: Int,
        triggeredBy: ShiftSource,
        sourceBlock: TimeBlockModel? = nil,
        event: EventModel,
        into context: ModelContext
    ) {
        let record = ShiftRecord(
            deltaMinutes: deltaMinutes,
            triggeredBy: triggeredBy,
            sourceBlock: sourceBlock,
            event: event
        )
        context.insert(record)
    }
}
