import SwiftData

/// Describes the evolution of the SHIFT schema across app versions.
///
/// - V1 → V2: adds vendor notification fields to `VendorModel`.
/// - V2 → V3: adds `EventModel.weatherSnapshot` and `TimeBlockModel.isOutdoor`.
/// - V3 → V4: adds per-block location fields (`venueAddress`, `venueName`,
///             `blockLatitude`, `blockLongitude`) to `TimeBlockModel`.
/// - V4 → V5: adds `TimeBlockModel.isTransitBlock` (default `false`).
/// - V5 → V6: adds `TimeBlockModel.completedTime` (`Date?`) and
///             `EventModel.postEventReportData` (`Data?`).
/// - V6 → V7: adds `EventModel.wentLiveAt` (`Date?`) and
///             `EventModel.completedAt` (`Date?`) for analytics.
/// - V7 → V8: adds `TimeBlockModel.voiceMemoDuration` (`TimeInterval?`) and
///             `TimeBlockModel.voiceMemoCreatedAt` (`Date?`) for voice memo metadata.
/// - V8 → V9: adds `VendorModel.invitedAt` (`Date?`) for invite-status tracking.
/// - V9 → V10: adds `EventModel.lastShiftedAt` (`Date?`) — CloudKit parent tickle.
/// - V10 → V11: drops CloudKit-only fields — `EventModel.shareURL`,
///              `EventModel.ownerRecordName`, `EventModel.lastShiftedAt`,
///              `VendorModel.cloudKitRecordName` (all `Optional`; lightweight).
/// - V11 → V12: adds `OutboxEntry` — the local offline write queue.
/// - V12 → V13: adds `OutboxEntry.sequence` (`Int`, default `0`) — the monotonic
///              FIFO/causality key for the offline SyncEngine.
/// - V13 → V14: adds `updatedAt` (`Date?`) to `EventModel`, `TimelineTrack`,
///              `TimeBlockModel`, `VendorModel` — the server-time basis for
///              last-write-wins conflict resolution.
/// - V14 → V15: adds `VendorModel.profileId` (`UUID?`) and
///              `VendorModel.acceptedAt` (`Date?`) — the claim-on-sign-in state
///              mirroring `event_vendors.profile_id` / `accepted_at`.
/// - V15 → V16: adds `EventModel.ownerId` (`UUID?`) mirroring `events.owner_id`
///              — distinguishes owned events from events shared to the user as a
///              vendor, so the latter render read-only.
/// - V16 → V17: adds `VendorModel.customRoleLabel` (`String`, default `""`) —
///              the user-entered vendor type shown when `role == .custom`.
///
/// All transitions are lightweight (new properties have defaults).
///
/// **Why this file exists:** SwiftData needs a `SchemaMigrationPlan` to migrate an
/// existing on-device store across schema versions without data loss.
///
/// **Critical:** Every `VersionedSchema` must contain frozen `@Model`
/// snapshots — not references to live model types. If two versions
/// reference the same live type, their checksums are identical and
/// `NSLightweightMigrationStage.init` throws an `NSException`, which
/// cascades through `PersistenceController`'s fallback chain and
/// aborts the store load.
public enum SHIFTMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [SHIFTSchemaV1.self, SHIFTSchemaV2.self, SHIFTSchemaV3.self, SHIFTSchemaV4.self, SHIFTSchemaV5.self, SHIFTSchemaV6.self, SHIFTSchemaV7.self, SHIFTSchemaV8.self, SHIFTSchemaV9.self, SHIFTSchemaV10.self, SHIFTSchemaV11.self, SHIFTSchemaV12.self, SHIFTSchemaV13.self, SHIFTSchemaV14.self, SHIFTSchemaV15.self, SHIFTSchemaV16.self, SHIFTSchemaV17.self]
    }

    public static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3, migrateV3toV4, migrateV4toV5, migrateV5toV6, migrateV6toV7, migrateV7toV8, migrateV8toV9, migrateV9toV10, migrateV10toV11, migrateV11toV12, migrateV12toV13, migrateV13toV14, migrateV14toV15, migrateV15toV16, migrateV16toV17]
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

    private static let migrateV8toV9 = MigrationStage.lightweight(
        fromVersion: SHIFTSchemaV8.self,
        toVersion: SHIFTSchemaV9.self
    )

    private static let migrateV9toV10 = MigrationStage.lightweight(
        fromVersion: SHIFTSchemaV9.self,
        toVersion: SHIFTSchemaV10.self
    )

    private static let migrateV10toV11 = MigrationStage.lightweight(
        fromVersion: SHIFTSchemaV10.self,
        toVersion: SHIFTSchemaV11.self
    )

    private static let migrateV11toV12 = MigrationStage.lightweight(
        fromVersion: SHIFTSchemaV11.self,
        toVersion: SHIFTSchemaV12.self
    )

    private static let migrateV12toV13 = MigrationStage.lightweight(
        fromVersion: SHIFTSchemaV12.self,
        toVersion: SHIFTSchemaV13.self
    )

    private static let migrateV13toV14 = MigrationStage.lightweight(
        fromVersion: SHIFTSchemaV13.self,
        toVersion: SHIFTSchemaV14.self
    )

    private static let migrateV14toV15 = MigrationStage.lightweight(
        fromVersion: SHIFTSchemaV14.self,
        toVersion: SHIFTSchemaV15.self
    )

    private static let migrateV15toV16 = MigrationStage.lightweight(
        fromVersion: SHIFTSchemaV15.self,
        toVersion: SHIFTSchemaV16.self
    )

    private static let migrateV16toV17 = MigrationStage.lightweight(
        fromVersion: SHIFTSchemaV16.self,
        toVersion: SHIFTSchemaV17.self
    )
}
