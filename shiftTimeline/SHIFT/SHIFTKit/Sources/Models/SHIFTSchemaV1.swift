import SwiftData

/// V1 schema snapshot wrapping all `@Model` classes as they existed at launch.
///
/// Future schema changes must define a new version and add a migration stage
/// in `SHIFTMigrationPlan`. Do **not** mutate this enum — version identity is
/// how SwiftData (and, crucially, CloudKit mirroring) tracks store evolution.
public enum SHIFTSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            EventModel.self,
            TimeBlockModel.self,
            TimelineTrack.self,
            VendorModel.self,
            ShiftRecord.self,
        ]
    }
}
