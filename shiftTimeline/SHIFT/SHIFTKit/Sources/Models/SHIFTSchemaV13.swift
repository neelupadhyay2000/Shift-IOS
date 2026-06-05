import Foundation
import SwiftData

/// V13 schema — adds `OutboxEntry.sequence` to the local store.
///
/// `sequence` is a monotonic, gap-free, strictly-increasing position assigned
/// per device at enqueue time. It is the authoritative FIFO key for the offline
/// SyncEngine (E13): entries flush in ascending `sequence` order so a parent row
/// enqueued before its child always flushes first (causality preservation). The
/// prior `createdAt`-only ordering had no deterministic tiebreaker on same-instant
/// writes, which could flush a child before its parent and trip a Postgres FK.
///
/// All other models (V12) are unchanged. Adding a new property with a default
/// value (`0`) is a lightweight migration.
public enum SHIFTSchemaV13: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(13, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            SHIFTSchemaV13.EventModel.self,
            SHIFTSchemaV13.TimeBlockModel.self,
            SHIFTSchemaV13.TimelineTrack.self,
            SHIFTSchemaV13.VendorModel.self,
            SHIFTSchemaV13.ShiftRecord.self,
            SHIFTSchemaV13.OutboxEntry.self,
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

    @Model
    public final class OutboxEntry {
        public var id: UUID = UUID()
        public var sequence: Int = 0
        public var tableName: String = ""
        public var rowID: UUID = UUID()
        public var operation: String = ""
        public var payload: Data?
        public var createdAt: Date = Date()
        public var attempts: Int = 0

        public init() {}
    }
}
