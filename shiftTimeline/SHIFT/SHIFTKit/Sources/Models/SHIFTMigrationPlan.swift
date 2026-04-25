import SwiftData

/// Describes the evolution of the SHIFT schema across app versions.
///
/// - V1 → V2: adds vendor notification fields to `VendorModel`.
/// - V2 → V3: adds `EventModel.weatherSnapshot` and `TimeBlockModel.isOutdoor`.
/// - V3 → V4: adds per-block location fields (`venueAddress`, `venueName`,
///             `blockLatitude`, `blockLongitude`) to `TimeBlockModel`.
/// - V4 → V5: adds `TimeBlockModel.isTransitBlock` (default `false`).
///
/// All transitions are lightweight (new properties have defaults).
///
/// **Why this file exists:** Without a `SchemaMigrationPlan`, SwiftData's
/// `NSPersistentCloudKitContainer` mirror treats post-change stores as
/// unversioned and silently stops publishing records to CloudKit.
///
/// **Critical:** Every `VersionedSchema` must contain frozen `@Model`
/// snapshots — not references to live model types. If two versions
/// reference the same live type, their checksums are identical and
/// `NSLightweightMigrationStage.init` throws an `NSException`, which
/// cascades through `PersistenceController`'s fallback chain and
/// silently disables CloudKit mirroring.
public enum SHIFTMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [SHIFTSchemaV1.self, SHIFTSchemaV2.self, SHIFTSchemaV3.self, SHIFTSchemaV4.self, SHIFTSchemaV5.self]
    }

    public static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3, migrateV3toV4, migrateV4toV5]
    }

    private static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: SHIFTSchemaV1.self,
        toVersion: SHIFTSchemaV2.self
    )

    private static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: SHIFTSchemaV2.self,
        toVersion: SHIFTSchemaV3.self
    )

    private static let migrateV3toV4 = MigrationStage.lightweight(
        fromVersion: SHIFTSchemaV3.self,
        toVersion: SHIFTSchemaV4.self
    )

    private static let migrateV4toV5 = MigrationStage.lightweight(
        fromVersion: SHIFTSchemaV4.self,
        toVersion: SHIFTSchemaV5.self
    )
}
