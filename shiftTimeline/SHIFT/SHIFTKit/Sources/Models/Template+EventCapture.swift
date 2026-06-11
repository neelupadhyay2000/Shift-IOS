import Foundation

public extension Template {

    /// Builds a reusable template from an event's live timeline blocks.
    ///
    /// Block start times are converted to offsets relative to the earliest
    /// scheduled start, so the resulting template is date-independent and can
    /// be applied to any future event exactly like a bundled starter template.
    static func captured(
        from blocks: [TimeBlockModel],
        name: String,
        description: String,
        category: TemplateCategory
    ) -> Template {
        let sorted = blocks.sorted { $0.scheduledStart < $1.scheduledStart }
        guard let anchor = sorted.first?.scheduledStart else {
            return Template(name: name, description: description, category: category, blocks: [])
        }
        let templateBlocks = sorted.map { block in
            TemplateBlock(
                title: block.title,
                relativeStartOffset: block.scheduledStart.timeIntervalSince(anchor),
                duration: block.duration,
                isPinned: block.isPinned,
                colorTag: block.colorTag,
                icon: block.icon
            )
        }
        return Template(name: name, description: description, category: category, blocks: templateBlocks)
    }
}
