import Foundation
import SwiftData

/// V9 schema — adds to `VendorModel`:
///   * `invitedAt: Date?` — when a locked CKShare invite was last sent to this
///     vendor. `nil` for contact-only vendors. Drives the invite-status chip
///     alongside the existing `cloudKitRecordName` (set on accept).
///
/// Why this snapshot exists: per the SHIFT-303 post-mortem, every new stored
/// property on a live `@Model` requires a frozen `VersionedSchema` snapshot or
/// `NSPersistentCloudKitContainer` silently halts mirroring. The
/// `CloudKitSyncIntegrityTests` reflection-based drift detector compares live
/// models against the latest snapshot (this one) and fails the build on drift.
///
/// **Critical:** Re-declares all `@Model` types in full so V9 has a distinct
/// schema checksum from V8; reusing live types would collapse both versions
/// onto the same checksum and cause `MigrationStage.lightweight(V8 → V9)`
/// to throw an `NSException`.
public enum SHIFTSchemaV9: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(9, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            SHIFTSchemaV9.EventModel.self,
            SHIFTSchemaV9.TimeBlockModel.self,
            SHIFTSchemaV9.TimelineTrack.self,
            SHIFTSchemaV9.VendorModel.self,
            SHIFTSchemaV9.ShiftRecord.self,
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
        public var voiceMemoDuration: TimeInterval?
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
        /// New in V9. When a locked CKShare invite was last sent to this vendor.
        public var invitedAt: Date?
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
