import Foundation
import SwiftData

/// V8 schema — adds to `TimeBlockModel`:
///   * `voiceMemoDuration: TimeInterval?` — duration in seconds of the attached
///     voice memo. `nil` when no memo is present.
///   * `voiceMemoCreatedAt: Date?` — wall-clock date the memo was recorded.
///     `nil` when no memo is present.
///
/// Why this snapshot exists: per the SHIFT-303 post-mortem, every new stored
/// property on a live `@Model` requires a frozen `VersionedSchema` snapshot or
/// `NSPersistentCloudKitContainer` silently halts mirroring.
/// The `CloudKitSyncIntegrityTests` reflection-based drift detector will
/// fail the build if the live model and this snapshot drift apart.
///
/// **Critical:** Re-declares all `@Model` types in full so V8 has a distinct
/// schema checksum from V7; reusing live types would collapse both versions
/// onto the same checksum and cause `MigrationStage.lightweight(V7 → V8)`
/// to throw.
///
/// **CloudKit note:** Only the `voiceMemoDuration` and `voiceMemoCreatedAt`
/// scalar fields sync via CloudKit. The audio file itself (`.m4a`) is stored
/// on-device only. Cross-device playback degrades gracefully via
/// `VoiceMemoStorage.resolve()` returning `nil` when the file is absent.
/// Full `CKAsset` audio sync is deferred to a follow-up ticket.
public enum SHIFTSchemaV8: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(8, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            SHIFTSchemaV8.EventModel.self,
            SHIFTSchemaV8.TimeBlockModel.self,
            SHIFTSchemaV8.TimelineTrack.self,
            SHIFTSchemaV8.VendorModel.self,
            SHIFTSchemaV8.ShiftRecord.self,
        ]
    }

    @Model
    public final class EventModel {
        public var id: UUID = UUID()
        public var title: String = ""
        public var date: Date = Date.distantPast
        public var latitude: Double = 0
        public var longitude: Double = 0
        public var venueNames: [String] = []
        public var sunsetTime: Date?
        public var goldenHourStart: Date?
        public var weatherSnapshot: Data?
        public var status: EventStatus = EventStatus.planning
        public var shareURL: String?
        public var ownerRecordName: String?
        public var postEventReportData: Data?
        public var wentLiveAt: Date?
        public var completedAt: Date?

        @Relationship(deleteRule: .cascade, inverse: \TimelineTrack.event)
        public var tracks: [TimelineTrack]?

        @Relationship(deleteRule: .cascade, inverse: \VendorModel.event)
        public var vendors: [VendorModel]?

        @Relationship(deleteRule: .cascade, inverse: \ShiftRecord.event)
        public var shiftRecords: [ShiftRecord]?

        public init() {}
    }

    @Model
    public final class TimeBlockModel {
        public var id: UUID = UUID()
        public var title: String = ""
        public var scheduledStart: Date = Date.distantPast
        public var originalStart: Date = Date.distantPast
        public var duration: TimeInterval = 0
        public var minimumDuration: TimeInterval = 0
        public var isPinned: Bool = false
        public var notes: String = ""
        public var voiceMemoURL: URL?
        /// New in V8. Duration (seconds) of the attached voice memo.
        public var voiceMemoDuration: TimeInterval?
        /// New in V8. Wall-clock date the voice memo was recorded.
        public var voiceMemoCreatedAt: Date?
        public var colorTag: String = "#007AFF"
        public var icon: String = "circle.fill"
        public var status: BlockStatus = BlockStatus.upcoming
        public var requiresReview: Bool = false
        public var isOutdoor: Bool = false
        public var venueAddress: String = ""
        public var venueName: String = ""
        public var blockLatitude: Double = 0
        public var blockLongitude: Double = 0
        public var isTransitBlock: Bool = false
        public var completedTime: Date?
        public var track: TimelineTrack?

        @Relationship(deleteRule: .nullify, inverse: \ShiftRecord.sourceBlock)
        public var shiftRecords: [ShiftRecord]?

        @Relationship(deleteRule: .nullify, inverse: \VendorModel.assignedBlocks)
        public var vendors: [VendorModel]?

        @Relationship(deleteRule: .nullify, inverse: \TimeBlockModel.dependents)
        public var dependencies: [TimeBlockModel]?

        @Relationship(deleteRule: .nullify)
        public var dependents: [TimeBlockModel]?

        public init() {}
    }

    @Model
    public final class TimelineTrack {
        public var id: UUID = UUID()
        public var name: String = ""
        public var sortOrder: Int = 0
        public var isDefault: Bool = false
        public var event: EventModel?

        @Relationship(deleteRule: .cascade, inverse: \TimeBlockModel.track)
        public var blocks: [TimeBlockModel]?

        public init() {}
    }

    @Model
    public final class VendorModel {
        public var id: UUID = UUID()
        public var name: String = ""
        public var role: VendorRole = VendorRole.custom
        public var phone: String = ""
        public var email: String = ""
        public var notificationThreshold: TimeInterval = 600
        public var hasAcknowledgedLatestShift: Bool = false
        public var pendingShiftDelta: TimeInterval?
        public var cloudKitRecordName: String?
        public var event: EventModel?

        @Relationship(deleteRule: .nullify)
        public var assignedBlocks: [TimeBlockModel]?

        public init() {}
    }

    @Model
    public final class ShiftRecord {
        public var id: UUID = UUID()
        public var timestamp: Date = Date()
        public var deltaMinutes: Int = 0
        public var triggeredBy: ShiftSource = ShiftSource.manual
        public var sourceBlock: TimeBlockModel?
        public var event: EventModel?

        public init() {}
    }
}
