import SwiftData

/// Describes the evolution of the SHIFT schema across app versions.
///
/// - V1 → V2: adds vendor notification fields to `VendorModel`.
/// - V2 → V3: adds `EventModel.weatherSnapshot` and `TimeBlockModel.isOutdoor`.
///
/// All transitions are lightweight (new properties have defaults).
///
/// **Why this file exists:** Without a `SchemaMigrationPlan`, SwiftData's
/// `NSPersistentCloudKitContainer` mirror treats post-change stores as
/// unversioned and silently stops publishing records to CloudKit, which is
/// what caused vendor sharing ("Did not find record type: CD_EventModel")
/// to fail after SHIFT-300.
public enum SHIFTMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [SHIFTSchemaV1.self, SHIFTSchemaV2.self, SHIFTSchemaV3.self]
    }

    public static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3]
    }

    private static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: SHIFTSchemaV1.self,
        toVersion: SHIFTSchemaV2.self
    )

    private static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: SHIFTSchemaV2.self,
        toVersion: SHIFTSchemaV3.self
    )
}
