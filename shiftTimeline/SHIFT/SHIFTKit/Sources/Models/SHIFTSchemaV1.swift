import SwiftData

/// V1 schema snapshot wrapping all current @Model classes.
///
/// Future schema changes should define a new `SHIFTSchemaV2` and add a
/// migration stage in `SHIFTMigrationPlan`.
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
