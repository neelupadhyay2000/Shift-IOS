import Foundation
import SwiftData

/// V11 schema — drops CloudKit-only fields from V10:
///   * `EventModel.shareURL` — CloudKit share link, ownership now in Supabase.
///   * `EventModel.ownerRecordName` — iCloud record name, replaced by `profiles.id`.
///   * `EventModel.lastShiftedAt` — CloudKit parent-tickle timestamp, no longer needed.
///   * `VendorModel.cloudKitRecordName` — iCloud identity, replaced by `profileId` (E-SB2).
///
/// All removed fields were `Optional`, so this is a lightweight migration —
/// existing rows simply lose those columns; no data transformation required.
///
/// Retained Supabase cache fields remain untouched:
/// `VendorModel.invitedAt`, `VendorModel.pendingShiftDelta`,
/// `VendorModel.hasAcknowledgedLatestShift`.
public enum SHIFTSchemaV11: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(11, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            SHIFTSchemaV11.EventModel.self,
            SHIFTSchemaV11.TimeBlockModel.self,
            SHIFTSchemaV11.TimelineTrack.self,
            SHIFTSchemaV11.VendorModel.self,
            SHIFTSchemaV11.ShiftRecord.self,
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
}
