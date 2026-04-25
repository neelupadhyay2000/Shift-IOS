import Foundation
import Models
import Services
import SwiftData
import Testing

/// Drift detector that fails the build whenever a stored property declared on
/// a live `@Model` type is missing from the corresponding model in
/// `SHIFTMigrationPlan.schemas.last`.
///
/// This is the exact regression class that broke CloudKit sync after SHIFT-303
/// added `TimeBlockModel.isTransitBlock` without a matching `SHIFTSchemaV5`.
/// The mirror checksum no longer matched any `VersionedSchema`, the migration
/// plan was rejected, and `NSPersistentCloudKitContainer` silently stopped
/// publishing records to iCloud.
///
/// If any of these tests fail, do NOT silence them — add a new
/// `SHIFTSchemaV{N+1}` snapshot containing the new property and append a
/// `migrateV{N}toV{N+1}` lightweight stage to `SHIFTMigrationPlan`.
@Suite("CloudKit Sync Integrity")
struct CloudKitSyncIntegrityTests {

    // MARK: - Helpers

    private static func liveModels() -> [any PersistentModel.Type] {
        [
            EventModel.self,
            TimeBlockModel.self,
            TimelineTrack.self,
            VendorModel.self,
            ShiftRecord.self,
        ]
    }

    /// Builds a name → property-set map from a list of models. Uses a single
    /// `Schema(...)` so SwiftData resolves all relationships in one graph and
    /// `entities` returns one `Entity` per model — keyed by `Entity.name`,
    /// which is the unqualified model class name (e.g. `"TimeBlockModel"`).
    private static func storedPropertyNamesByEntity(
        for models: [any PersistentModel.Type]
    ) -> [String: Set<String>] {
        let schema = Schema(models)
        var dict: [String: Set<String>] = [:]
        for entity in schema.entities {
            let attributes = entity.attributes.map(\.name)
            let relationships = entity.relationships.map(\.name)
            dict[entity.name] = Set(attributes).union(relationships)
        }
        return dict
    }

    // MARK: - Drift Detector

    /// Every stored property on every live `@Model` must also exist on the
    /// matching model inside the latest `VersionedSchema` snapshot.
    @Test func liveModelMatchesLatestVersionedSchema() {
        let livePropsByName = Self.storedPropertyNamesByEntity(for: Self.liveModels())
        let snapshotPropsByName = Self.storedPropertyNamesByEntity(
            for: SHIFTMigrationPlan.schemas.last?.models ?? []
        )

        for (entityName, liveProps) in livePropsByName {
            guard let snapshotProps = snapshotPropsByName[entityName] else {
                Issue.record("Live model `\(entityName)` is missing from the latest VersionedSchema in SHIFTMigrationPlan")
                continue
            }

            let missing = liveProps.subtracting(snapshotProps)
            #expect(
                missing.isEmpty,
                "Live `\(entityName)` declares stored properties absent from the latest VersionedSchema: \(missing.sorted()). Add a new SHIFTSchemaV{N+1} snapshot containing these properties and a corresponding lightweight MigrationStage."
            )
        }
    }

    /// Targeted regression: the property that broke sync in SHIFT-303 must be
    /// present on the latest `VersionedSchema`'s `TimeBlockModel`.
    @Test func isTransitBlockPropertyIsMirroredInLatestSchema() {
        let snapshotPropsByName = Self.storedPropertyNamesByEntity(
            for: SHIFTMigrationPlan.schemas.last?.models ?? []
        )
        guard let snapshotProps = snapshotPropsByName["TimeBlockModel"] else {
            Issue.record("TimeBlockModel missing from latest VersionedSchema")
            return
        }
        #expect(
            snapshotProps.contains("isTransitBlock"),
            "Live `TimeBlockModel` declares `isTransitBlock` but it is missing from the latest VersionedSchema. CloudKit mirror will silently halt until a SHIFTSchemaV{N+1} snapshot adds this property."
        )
    }
}
