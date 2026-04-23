import SwiftData

/// V2 schema — adds vendor notification fields to `VendorModel`:
///   - `notificationThreshold: TimeInterval` (default 600)
///   - `pendingShiftDelta: TimeInterval?`
///   - `hasAcknowledgedLatestShift: Bool`
///
/// All new properties have defaults, so a lightweight migration from V1 is sufficient.
public enum SHIFTSchemaV2: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

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
