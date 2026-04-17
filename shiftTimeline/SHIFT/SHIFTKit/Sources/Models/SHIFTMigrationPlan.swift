import SwiftData

/// Describes the evolution of the SHIFT schema across app versions.
///
/// V1 → V2: Adds vendor notification fields (`notificationThreshold`,
/// `pendingShiftDelta`, `hasAcknowledgedLatestShift`) to `VendorModel`.
/// All new properties have defaults, so lightweight migration suffices.
public enum SHIFTMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [SHIFTSchemaV1.self, SHIFTSchemaV2.self]
    }

    public static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    private static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: SHIFTSchemaV1.self,
        toVersion: SHIFTSchemaV2.self
    )
}
