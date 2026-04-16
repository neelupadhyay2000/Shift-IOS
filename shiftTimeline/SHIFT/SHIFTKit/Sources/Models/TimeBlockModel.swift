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
