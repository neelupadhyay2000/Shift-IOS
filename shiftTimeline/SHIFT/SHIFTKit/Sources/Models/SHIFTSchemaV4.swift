import Foundation
import SwiftData

/// V4 schema — adds per-block location fields to `TimeBlockModel`:
///   - `venueAddress: String` (default `""`)
///   - `venueName: String` (default `""`)
///   - `blockLatitude: Double` (default `0`)
///   - `blockLongitude: Double` (default `0`)
///
/// All new properties have defaults, so a lightweight migration from V3 suffices.
public enum SHIFTSchemaV4: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            EventModel.self,
            TimeBlockModel.self,
            TimelineTrack.self,
            VendorModel.self,
            ShiftRecord.self,
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
        public var colorTag: String = "#007AFF"
        public var icon: String = "circle.fill"
        public var status: BlockStatus = BlockStatus.upcoming
        public var requiresReview: Bool = false
        public var isOutdoor: Bool = false
        public var venueAddress: String = ""
        public var venueName: String = ""
        public var blockLatitude: Double = 0
        public var blockLongitude: Double = 0
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
