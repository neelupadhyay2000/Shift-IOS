import SwiftData

/// Describes the evolution of the SHIFT schema across app versions.
///
/// Currently contains only V1 with no migration stages.
/// When a V2 is added, insert a `.lightweight(fromVersion:toVersion:)`
/// or `.custom(fromVersion:toVersion:willMigrate:didMigrate:)` stage.
public enum SHIFTMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [SHIFTSchemaV1.self]
    }

    public static var stages: [MigrationStage] {
        []
    }
}
