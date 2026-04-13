import Foundation
import SwiftData

@Model
public final class TimeBlockModel {
    public var id: UUID
    public var title: String
    public var scheduledStart: Date
    public var originalStart: Date
    public var duration: TimeInterval
    public var minimumDuration: TimeInterval
    public var isPinned: Bool
    public var notes: String
    public var voiceMemoURL: URL?
    public var colorTag: String
    public var icon: String
    public var status: BlockStatus
    public var requiresReview: Bool
    public var track: TimelineTrack?

    @Relationship(deleteRule: .nullify, inverse: \ShiftRecord.sourceBlock)
    public var shiftRecords: [ShiftRecord] = []

    @Relationship(deleteRule: .nullify)
    public var vendors: [VendorModel] = []

    @Relationship(deleteRule: .nullify)
    public var dependencies: [TimeBlockModel] = []

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
