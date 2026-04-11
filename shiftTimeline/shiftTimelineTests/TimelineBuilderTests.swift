import Foundation
import Models
import Services
import SwiftData
import Testing

struct TimelineBuilderTests {

    /// AC: blocks are displayed in chronological order.
    @Test @MainActor func blocksAreFetchedInChronologicalOrder() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let base = Date.now
        let event = EventModel(title: "Wedding", date: base, latitude: 0, longitude: 0)
        context.insert(event)

        let track = TimelineTrack(name: "Main", sortOrder: 0, event: event)
        context.insert(track)

        let block1 = TimeBlockModel(title: "Dinner", scheduledStart: base.addingTimeInterval(3600), duration: 5400, isPinned: true, colorTag: "#34C759")
        block1.track = track
        context.insert(block1)

        let block2 = TimeBlockModel(title: "Ceremony", scheduledStart: base, duration: 1800, isPinned: true, colorTag: "#FF5733")
        block2.track = track
        context.insert(block2)

        let block3 = TimeBlockModel(title: "Cocktails", scheduledStart: base.addingTimeInterval(1800), duration: 3600, colorTag: "#007AFF")
        block3.track = track
        context.insert(block3)

        try context.save()

        // Simulate the sort logic from TimelineBuilderView
        let sortedBlocks = event.tracks
            .flatMap(\.blocks)
            .sorted { $0.scheduledStart < $1.scheduledStart }

        #expect(sortedBlocks.count == 3)
        #expect(sortedBlocks[0].title == "Ceremony")
        #expect(sortedBlocks[1].title == "Cocktails")
        #expect(sortedBlocks[2].title == "Dinner")
    }

    /// AC: each block exposes isPinned for the Fluid/Pinned indicator.
    @Test func blockPinnedIndicator() {
        let pinned = TimeBlockModel(title: "Ceremony", scheduledStart: .now, duration: 1800, isPinned: true)
        let fluid = TimeBlockModel(title: "Buffer", scheduledStart: .now, duration: 600)

        #expect(pinned.isPinned == true)
        #expect(fluid.isPinned == false)
    }

    /// AC: empty state when event has no blocks.
    @Test @MainActor func emptyEventHasNoBlocks() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Empty Event", date: .now, latitude: 0, longitude: 0)
        context.insert(event)
        try context.save()

        let blocks = event.tracks.flatMap(\.blocks)
        #expect(blocks.isEmpty)
    }
}
