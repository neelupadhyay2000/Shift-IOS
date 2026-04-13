import Foundation

/// A category for grouping event templates.
public enum TemplateCategory: String, Codable, Sendable, CaseIterable {
    case wedding
    case corporate
    case social
    case photography
}

/// A single block definition within a template.
/// Uses relative offsets so templates are date-independent.
public struct TemplateBlock: Codable, Sendable, Equatable {
    /// Display title for the block (e.g. "Ceremony").
    public let title: String
    /// Seconds from the event start time to this block's start.
    public let relativeStartOffset: TimeInterval
    /// Duration of the block in seconds.
    public let duration: TimeInterval
    /// Whether this block is pinned (immovable).
    public let isPinned: Bool
    /// Hex color tag (e.g. "#FF3B30").
    public let colorTag: String
    /// SF Symbol name for the block icon.
    public let icon: String

    public init(
        title: String,
        relativeStartOffset: TimeInterval,
        duration: TimeInterval,
        isPinned: Bool = false,
        colorTag: String = "#007AFF",
        icon: String = "circle.fill"
    ) {
        self.title = title
        self.relativeStartOffset = relativeStartOffset
        self.duration = duration
        self.isPinned = isPinned
        self.colorTag = colorTag
        self.icon = icon
    }
}

/// A reusable event template that can be applied to create a pre-built timeline.
public struct Template: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    /// Human-readable template name.
    public let name: String
    /// Short description of what this template covers.
    public let description: String
    /// Category for filtering/grouping templates.
    public let category: TemplateCategory
    /// Ordered list of blocks that make up this template.
    public let blocks: [TemplateBlock]

    public init(
        id: UUID = UUID(),
        name: String,
        description: String,
        category: TemplateCategory,
        blocks: [TemplateBlock]
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.blocks = blocks
    }
}
