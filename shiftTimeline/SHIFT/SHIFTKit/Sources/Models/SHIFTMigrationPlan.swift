import SwiftData

/// Lightweight SwiftData schema migration plan. V1→V8, all transitions add new optional/defaulted properties.
/// CRITICAL: Each `VersionedSchema` must use frozen `@Model` snapshots — never live type references.
public enum SHIFTMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [SHIFTSchemaV1.self, SHIFTSchemaV2.self, SHIFTSchemaV3.self, SHIFTSchemaV4.self, SHIFTSchemaV5.self, SHIFTSchemaV6.self, SHIFTSchemaV7.self, SHIFTSchemaV8.self]
    }

    public static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3, migrateV3toV4, migrateV4toV5, migrateV5toV6, migrateV6toV7, migrateV7toV8]
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

    private static let migrateV5toV6 = MigrationStage.lightweight(
        fromVersion: SHIFTSchemaV5.self,
        toVersion: SHIFTSchemaV6.self
    )

    private static let migrateV6toV7 = MigrationStage.lightweight(
        fromVersion: SHIFTSchemaV6.self,
        toVersion: SHIFTSchemaV7.self
    )

    private static let migrateV7toV8 = MigrationStage.lightweight(
        fromVersion: SHIFTSchemaV7.self,
        toVersion: SHIFTSchemaV8.self
    )
}
