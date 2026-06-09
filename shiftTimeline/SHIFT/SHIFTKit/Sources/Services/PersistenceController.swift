import Foundation
import os
import SwiftData
import Models
import ObjCException

/// Local-first SwiftData persistence layer.
///
/// The store is configured with `cloudKitDatabase: .none`, so it never mirrors to
/// CloudKit and the app runs fully offline with no iCloud account required. Sync
/// and sharing are handled separately by the Supabase backend.
public final class PersistenceController: Sendable {

    private static let logger = Logger(subsystem: "com.shift.persistence", category: "store")

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
            OutboxEntry.self,
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
            cloudKitDatabase: .none
        )

        // Attempt 1: existing on-disk store with migration plan (happy path).
        if let built = Self.tryBuildContainer(
            schema: schema,
            configuration: config,
            migrationPlan: SHIFTMigrationPlan.self,
            label: "existing store"
        ) {
            container = built
            return
        }

        // Attempt 2: corrupt or outdated store — delete and retry.
        Self.logger.error("Store init failed — deleting and retrying")
        Self.deleteStoreFiles(at: url)

        if let built = Self.tryBuildContainer(
            schema: schema,
            configuration: config,
            migrationPlan: SHIFTMigrationPlan.self,
            label: "fresh store"
        ) {
            container = built
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

    /// Creates and inserts a `ShiftRecord` documenting a committed shift.
    ///
    /// Call this immediately before `context.save()` at every shift commit
    /// site (iPhone UI, Watch bridge, AppIntent) so `event.shiftRecords` and
    /// `PostEventReport.totalShiftCount` are populated correctly.
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
