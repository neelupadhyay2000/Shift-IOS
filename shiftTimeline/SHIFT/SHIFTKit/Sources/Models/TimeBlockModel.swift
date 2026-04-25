import Foundation
import SwiftData

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
    /// Human-readable venue address for this specific block (e.g. "St. Mary's Church, 123 Main St").
    public var venueAddress: String = ""
    /// Display name of the venue resolved from MapKit (e.g. "St. Mary's Church").
    public var venueName: String = ""
    /// Latitude resolved from MapKit for this block's venue. 0 means not set.
    public var blockLatitude: Double = 0
    /// Longitude resolved from MapKit for this block's venue. 0 means not set.
    public var blockLongitude: Double = 0
    /// True when this block was auto-inserted as a transit/driving block between
    /// two venues. Used to exclude it from venue-switch detection so transit
    /// blocks don't trigger nested transit prompts.
    public var isTransitBlock: Bool = false
    /// Wall-clock time the block was marked `.completed` during live execution.
    /// `nil` for blocks that were never completed (cancelled, skipped, or the
    /// event ended early). Sourced by `PostEventReportGenerator` as the
    /// `actualCompletion` time when comparing planned vs. actual drift.
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

    public init(
        id: UUID = UUID(),
        title: String,
        scheduledStart: Date,
        originalStart: Date? = nil,
        duration: TimeInterval,
        minimumDuration: TimeInterval = 0,
        isPinned: Bool = false,
        notes: String = "",
        voiceMemoURL: URL? = nil,
        colorTag: String = "#007AFF",
        icon: String = "circle.fill",
        status: BlockStatus = .upcoming,
        requiresReview: Bool = false
    ) {
        self.id = id
        self.title = title
        self.scheduledStart = scheduledStart
        self.originalStart = originalStart ?? scheduledStart
        self.duration = duration
        self.minimumDuration = minimumDuration
        self.isPinned = isPinned
        self.notes = notes
        self.voiceMemoURL = voiceMemoURL
        self.colorTag = colorTag
        self.icon = icon
        self.status = status
        self.requiresReview = requiresReview
    }
}
