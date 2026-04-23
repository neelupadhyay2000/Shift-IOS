import SwiftData

/// V3 schema — adds weather-warning fields:
///   - `EventModel.weatherSnapshot: Data?`
///   - `TimeBlockModel.isOutdoor: Bool` (default `false`)
///
/// All new properties have defaults, so a lightweight migration from V2 is sufficient.
/// Critical: a stable, versioned schema identity is required for
/// `NSPersistentCloudKitContainer` mirroring to continue publishing records
/// after schema changes. Omitting this breaks CloudKit sync silently.
public enum SHIFTSchemaV3: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

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
