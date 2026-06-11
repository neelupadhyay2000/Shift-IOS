import Foundation
import Models
import Testing
@testable import shiftTimeline

/// Covers `Template.captured(from:)` — building a reusable, date-independent
/// template from an event's live timeline blocks.
struct TemplateCaptureTests {

    private let base = Date(timeIntervalSince1970: 1_750_000_000)

    @Test func capturedAnchorsOffsetsToEarliestBlock() {
        let blocks = [
            TimeBlockModel(title: "Ceremony", scheduledStart: base.addingTimeInterval(3600), duration: 1800),
            TimeBlockModel(title: "Prep", scheduledStart: base, duration: 3600),
        ]

        let template = Template.captured(
            from: blocks,
            name: "My Wedding",
            description: "Saved from event",
            category: .wedding
        )

        #expect(template.blocks.map(\.relativeStartOffset) == [0, 3600])
    }

    @Test func capturedSortsBlocksByScheduledStart() {
        let blocks = [
            TimeBlockModel(title: "Third", scheduledStart: base.addingTimeInterval(7200), duration: 600),
            TimeBlockModel(title: "First", scheduledStart: base, duration: 600),
            TimeBlockModel(title: "Second", scheduledStart: base.addingTimeInterval(3600), duration: 600),
        ]

        let template = Template.captured(from: blocks, name: "Order", description: "", category: .social)

        #expect(template.blocks.map(\.title) == ["First", "Second", "Third"])
    }

    @Test func capturedPreservesBlockAttributes() {
        let block = TimeBlockModel(
            title: "Golden Hour Portraits",
            scheduledStart: base,
            duration: 2700,
            isPinned: true,
            colorTag: "#FF9500",
            icon: "sun.horizon.fill"
        )

        let template = Template.captured(from: [block], name: "Portraits", description: "", category: .photography)

        let captured = template.blocks.first
        #expect(captured?.title == "Golden Hour Portraits")
        #expect(captured?.duration == 2700)
        #expect(captured?.isPinned == true)
        #expect(captured?.colorTag == "#FF9500")
        #expect(captured?.icon == "sun.horizon.fill")
    }

    @Test func capturedPreservesNameDescriptionAndCategory() {
        let template = Template.captured(
            from: [TimeBlockModel(title: "Block", scheduledStart: base, duration: 600)],
            name: "Corporate Gala",
            description: "Annual gala run-sheet",
            category: .corporate
        )

        #expect(template.name == "Corporate Gala")
        #expect(template.description == "Annual gala run-sheet")
        #expect(template.category == .corporate)
    }

    @Test func capturedWithNoBlocksProducesEmptyTemplate() {
        let template = Template.captured(from: [], name: "Empty", description: "", category: .social)
        #expect(template.blocks.isEmpty)
    }

    @Test func capturedTemplateRoundTripsThroughJSON() throws {
        let blocks = [
            TimeBlockModel(title: "Prep", scheduledStart: base, duration: 3600),
            TimeBlockModel(
                title: "Ceremony",
                scheduledStart: base.addingTimeInterval(3600),
                duration: 1800,
                isPinned: true
            ),
        ]
        let template = Template.captured(from: blocks, name: "Round Trip", description: "", category: .wedding)

        let data = try JSONEncoder().encode(template)
        let decoded = try JSONDecoder().decode(Template.self, from: data)

        #expect(decoded == template)
    }
}
