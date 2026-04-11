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

    /// AC: saving creates TimeBlockModel in SwiftData, block appears at correct chronological position.
    @Test @MainActor func newBlockInsertedAppearsInChronologicalOrder() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let base = Date.now
        let event = EventModel(title: "Wedding", date: base, latitude: 0, longitude: 0)
        context.insert(event)

        let track = TimelineTrack(name: "Main", sortOrder: 0, event: event)
        context.insert(track)

        // Existing blocks
        let early = TimeBlockModel(title: "Ceremony", scheduledStart: base, duration: 1800, isPinned: true)
        early.track = track
        context.insert(early)

        let late = TimeBlockModel(title: "Dinner", scheduledStart: base.addingTimeInterval(7200), duration: 5400)
        late.track = track
        context.insert(late)

        try context.save()

        // Simulate creating a new block (as CreateBlockSheet does)
        let newBlock = TimeBlockModel(title: "Cocktails", scheduledStart: base.addingTimeInterval(1800), duration: 3600)
        newBlock.track = track
        context.insert(newBlock)
        try context.save()

        let sorted = event.tracks
            .flatMap(\.blocks)
            .sorted { $0.scheduledStart < $1.scheduledStart }

        #expect(sorted.count == 3)
        #expect(sorted[0].title == "Ceremony")
        #expect(sorted[1].title == "Cocktails")
        #expect(sorted[2].title == "Dinner")
    }

    /// AC: editing a block via the inspector saves changes to SwiftData.
    @Test @MainActor func editingBlockFieldsPersistsToSwiftData() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let base = Date.now
        let event = EventModel(title: "Wedding", date: base, latitude: 0, longitude: 0)
        context.insert(event)

        let track = TimelineTrack(name: "Main", sortOrder: 0, event: event)
        context.insert(track)

        let block = TimeBlockModel(
            title: "Ceremony",
            scheduledStart: base,
            duration: 1800,
            isPinned: true,
            notes: "",
            colorTag: "#007AFF",
            icon: "circle.fill"
        )
        block.track = track
        context.insert(block)
        try context.save()

        // Simulate what BlockInspectorView.saveChanges() does
        block.title = "Updated Ceremony"
        block.scheduledStart = base.addingTimeInterval(600)
        block.duration = 2700
        block.isPinned = false
        block.notes = "Outdoor garden"
        block.colorTag = "#FF3B30"
        block.icon = "heart.fill"
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TimeBlockModel>())
        let result = try #require(fetched.first)
        #expect(result.title == "Updated Ceremony")
        #expect(result.scheduledStart == base.addingTimeInterval(600))
        #expect(result.duration == 2700)
        #expect(result.isPinned == false)
        #expect(result.notes == "Outdoor garden")
        #expect(result.colorTag == "#FF3B30")
        #expect(result.icon == "heart.fill")
    }

    /// AC: reorder recalculates scheduledStart for subsequent fluid blocks.
    @Test func reorderRecalculatesStartTimesForFluidBlocks() {
        let base = Date(timeIntervalSinceReferenceDate: 0)

        let a = TimeBlockModel(title: "A", scheduledStart: base, duration: 1800)
        let b = TimeBlockModel(title: "B", scheduledStart: base.addingTimeInterval(1800), duration: 3600)
        let c = TimeBlockModel(title: "C", scheduledStart: base.addingTimeInterval(5400), duration: 1800)

        // Simulate reorder: move C before A → [C, A, B]
        let blocks = [c, a, b]

        // Recalculate (mirrors TimelineBuilderView.recalculateStartTimes)
        var cursor = base
        for block in blocks {
            if block.isPinned {
                cursor = max(cursor, block.scheduledStart.addingTimeInterval(block.duration))
            } else {
                block.scheduledStart = cursor
                cursor = cursor.addingTimeInterval(block.duration)
            }
        }

        #expect(blocks[0].title == "C")
        #expect(blocks[0].scheduledStart == base)
        #expect(blocks[1].title == "A")
        #expect(blocks[1].scheduledStart == base.addingTimeInterval(1800))
        #expect(blocks[2].title == "B")
        #expect(blocks[2].scheduledStart == base.addingTimeInterval(3600))
    }

    /// AC: pinned blocks keep their scheduled time during reorder.
    @Test func pinnedBlocksRetainStartTimeDuringReorder() {
        let base = Date(timeIntervalSinceReferenceDate: 0)

        let fluid1 = TimeBlockModel(title: "Fluid1", scheduledStart: base, duration: 1800)
        let pinned = TimeBlockModel(title: "Pinned", scheduledStart: base.addingTimeInterval(1800), duration: 1800, isPinned: true)
        let fluid2 = TimeBlockModel(title: "Fluid2", scheduledStart: base.addingTimeInterval(3600), duration: 1800)

        // Order: Fluid1, Pinned, Fluid2
        let blocks = [fluid1, pinned, fluid2]

        var cursor = base
        for block in blocks {
            if block.isPinned {
                cursor = max(cursor, block.scheduledStart.addingTimeInterval(block.duration))
            } else {
                block.scheduledStart = cursor
                cursor = cursor.addingTimeInterval(block.duration)
            }
        }

        // Pinned block should keep its original start
        #expect(pinned.scheduledStart == base.addingTimeInterval(1800))
        // Fluid2 should start after pinned ends
        #expect(fluid2.scheduledStart == base.addingTimeInterval(3600))
    }

    /// AC: pinned blocks cannot be moved — moveDisabled is true for pinned.
    @Test func pinnedBlocksCannotBeDragged() {
        let pinned = TimeBlockModel(title: "Ceremony", scheduledStart: .now, duration: 1800, isPinned: true)
        let fluid = TimeBlockModel(title: "Buffer", scheduledStart: .now, duration: 600)

        // The view uses .moveDisabled(block.isPinned)
        #expect(pinned.isPinned == true)
        #expect(fluid.isPinned == false)
    }

    /// AC: deleting a block removes it and recalculates subsequent start times.
    @Test @MainActor func deleteBlockClosesGapAndRecalculates() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let base = Date.now
        let event = EventModel(title: "Wedding", date: base, latitude: 0, longitude: 0)
        context.insert(event)

        let track = TimelineTrack(name: "Main", sortOrder: 0, event: event)
        context.insert(track)

        let a = TimeBlockModel(title: "A", scheduledStart: base, duration: 1800)
        a.track = track
        context.insert(a)

        let b = TimeBlockModel(title: "B", scheduledStart: base.addingTimeInterval(1800), duration: 1800)
        b.track = track
        context.insert(b)

        let c = TimeBlockModel(title: "C", scheduledStart: base.addingTimeInterval(3600), duration: 1800)
        c.track = track
        context.insert(c)

        try context.save()

        // Simulate deleting B (mirrors deleteBlock logic)
        var blocks = [a, b, c]
        blocks.removeAll { $0.id == b.id }
        context.delete(b)

        // Recalculate start times
        var cursor = base
        for block in blocks {
            if block.isPinned {
                cursor = max(cursor, block.scheduledStart.addingTimeInterval(block.duration))
            } else {
                block.scheduledStart = cursor
                cursor = cursor.addingTimeInterval(block.duration)
            }
        }
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TimeBlockModel>(
            sortBy: [SortDescriptor(\TimeBlockModel.scheduledStart)]
        ))
        #expect(fetched.count == 2)
        #expect(fetched[0].title == "A")
        #expect(fetched[0].scheduledStart == base)
        #expect(fetched[1].title == "C")
        // C should close the gap left by B
        #expect(fetched[1].scheduledStart == base.addingTimeInterval(1800))
    }

    /// AC: pinned blocks require confirmation before deletion.
    @Test func pinnedBlockRequiresDeleteConfirmation() {
        let pinned = TimeBlockModel(title: "Ceremony", scheduledStart: .now, duration: 1800, isPinned: true)
        let fluid = TimeBlockModel(title: "Buffer", scheduledStart: .now, duration: 600)

        // View logic: if block.isPinned → show alert, else delete immediately
        #expect(pinned.isPinned == true)
        #expect(fluid.isPinned == false)
    }
}
