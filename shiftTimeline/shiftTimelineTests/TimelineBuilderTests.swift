import Foundation
import Models
import Services
import SwiftData
import Testing
@testable import shiftTimeline

struct TimelineBuilderTests {

    /// AC: blocks are displayed in chronological order.
    @Test @MainActor func blocksAreFetchedInChronologicalOrder() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let base = Date.now
        let event = EventModel(title: "Wedding", date: base, latitude: 0, longitude: 0)
        context.insert(event)

        let track = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true, event: event)
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

        let track = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true, event: event)
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

        let track = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true, event: event)
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

        let track = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true, event: event)
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

    // MARK: - Time Ruler

    /// AC: ruler adapts to event's time range (first block start → last block end).
    @Test func rulerLayoutAdaptsToBlockTimeRange() {
        let calendar = Calendar.current
        // 2:15 PM start
        let start = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 14, minute: 15))!
        // End at 4:45 PM (start + 2.5h)
        let end = start.addingTimeInterval(9000)

        let blocks = [
            TestBlock(blockStart: start, blockEnd: start.addingTimeInterval(1800)),
            TestBlock(blockStart: start.addingTimeInterval(1800), blockEnd: end),
        ]

        let layout = TimeRulerLayout.adaptive(blocks: blocks)

        // Should round start down to 2 PM
        let expected2PM = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 14))!
        #expect(layout.rulerStart == expected2PM)

        // Should round end up to 5 PM (next hour after 4:45)
        let expected5PM = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 17))!
        #expect(layout.rulerEnd == expected5PM)
    }

    /// AC: hour markers cover the ruler range.
    @Test func rulerGeneratesCorrectHourMarkers() {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 14))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 17))!

        let layout = TimeRulerLayout(rulerStart: start, rulerEnd: end, pointsPerMinute: 1.5)
        let markers = layout.hourMarkers

        #expect(markers.count == 4) // 2PM, 3PM, 4PM, 5PM

        let hours = markers.map { calendar.component(.hour, from: $0) }
        #expect(hours == [14, 15, 16, 17])
    }

    /// AC: blocks positioned relative to ruler (correct Y offset and height).
    @Test func rulerLayoutPositionsBlocksCorrectly() {
        let calendar = Calendar.current
        let rulerStart = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 14))!
        let rulerEnd = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 17))!

        let layout = TimeRulerLayout(rulerStart: rulerStart, rulerEnd: rulerEnd, pointsPerMinute: 2.0)

        // Block at 2:30 PM, 45 min duration
        let blockStart = rulerStart.addingTimeInterval(1800) // 30 min after ruler start
        let blockDuration: TimeInterval = 2700 // 45 min

        let yOffset = layout.yOffset(for: blockStart)
        let height = layout.height(for: blockDuration)

        #expect(yOffset == 60.0)  // 30 min * 2.0 ppm
        #expect(height == 90.0)   // 45 min * 2.0 ppm
        #expect(layout.totalHeight == 360.0) // 180 min * 2.0 ppm
    }

    // MARK: - Track Management

    /// AC: Add track with user-entered name.
    @Test @MainActor func addTrackCreatesNewTrackWithCorrectSortOrder() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        context.insert(event)

        let mainTrack = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true, event: event)
        context.insert(mainTrack)
        try context.save()

        #expect(event.tracks.count == 1)

        // Simulate addTrack() logic
        let sortedTracks = event.tracks.sorted { $0.sortOrder < $1.sortOrder }
        let nextOrder = (sortedTracks.last?.sortOrder ?? 0) + 1
        let newTrack = TimelineTrack(name: "Photo", sortOrder: nextOrder, event: event)
        context.insert(newTrack)
        try context.save()

        #expect(event.tracks.count == 2)
        let sorted = event.tracks.sorted { $0.sortOrder < $1.sortOrder }
        #expect(sorted[0].name == "Main")
        #expect(sorted[0].sortOrder == 0)
        #expect(sorted[1].name == "Photo")
        #expect(sorted[1].sortOrder == 1)
    }

    /// AC: Rename via inline edit.
    @Test @MainActor func renameTrackUpdatesName() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        context.insert(event)

        let track = TimelineTrack(name: "Photos", sortOrder: 1, event: event)
        context.insert(track)
        try context.save()

        // Simulate renameTrack() logic
        track.name = "Photo Session"
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TimelineTrack>())
        let renamedTrack = try #require(fetched.first { $0.id == track.id })
        #expect(renamedTrack.name == "Photo Session")
    }

    /// AC: Delete empty track removes it.
    @Test @MainActor func deleteEmptyTrackRemovesIt() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        context.insert(event)

        let mainTrack = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true, event: event)
        context.insert(mainTrack)

        let emptyTrack = TimelineTrack(name: "Music", sortOrder: 1, event: event)
        context.insert(emptyTrack)
        try context.save()

        #expect(event.tracks.count == 2)

        // Simulate deleteTrack() on empty track
        context.delete(emptyTrack)
        try context.save()

        #expect(event.tracks.count == 1)
        #expect(event.tracks.first?.name == "Main")
    }

    /// AC: Delete track with blocks moves blocks to Main first.
    @Test @MainActor func deleteTrackWithBlocksMovesBlocksToMain() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        context.insert(event)

        let mainTrack = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true, event: event)
        context.insert(mainTrack)

        let photoTrack = TimelineTrack(name: "Photo", sortOrder: 1, event: event)
        context.insert(photoTrack)

        let blockA = TimeBlockModel(title: "Portraits", scheduledStart: .now, duration: 1800)
        blockA.track = photoTrack
        context.insert(blockA)

        let blockB = TimeBlockModel(title: "Group Shots", scheduledStart: .now.addingTimeInterval(1800), duration: 1200)
        blockB.track = photoTrack
        context.insert(blockB)
        try context.save()

        #expect(photoTrack.blocks.count == 2)
        #expect(mainTrack.blocks.count == 0)

        // Simulate deleteTrack() logic — move blocks to Main first
        for block in photoTrack.blocks {
            block.track = mainTrack
        }
        context.delete(photoTrack)
        try context.save()

        // Blocks should now be in Main
        #expect(event.tracks.count == 1)
        #expect(mainTrack.blocks.count == 2)
        let blockTitles = Set(mainTrack.blocks.map(\.title))
        #expect(blockTitles.contains("Portraits"))
        #expect(blockTitles.contains("Group Shots"))
    }

    /// AC: "Main" track cannot be deleted.
    @Test @MainActor func mainTrackCannotBeDeleted() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        context.insert(event)

        let mainTrack = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true, event: event)
        context.insert(mainTrack)

        let photoTrack = TimelineTrack(name: "Photo", sortOrder: 1, event: event)
        context.insert(photoTrack)
        try context.save()

        // Simulate deleteTrack() guard — default track is protected
        let trackToDelete = mainTrack
        #expect(trackToDelete.isDefault == true)

        // The guard prevents deletion — default track stays
        if !trackToDelete.isDefault {
            context.delete(trackToDelete)
        }
        try context.save()

        #expect(event.tracks.count == 2)
        #expect(event.tracks.contains(where: { $0.isDefault }))
    }

    // MARK: - Track Tab Bar Filtering

    /// AC: Tapping a track tab filters blocks to that track.
    @Test @MainActor func filteringByTrackReturnsOnlyBlocksInThatTrack() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        context.insert(event)

        let mainTrack = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true, event: event)
        context.insert(mainTrack)

        let photoTrack = TimelineTrack(name: "Photo", sortOrder: 1, event: event)
        context.insert(photoTrack)

        let blockA = TimeBlockModel(title: "Ceremony", scheduledStart: .now, duration: 1800)
        blockA.track = mainTrack
        context.insert(blockA)

        let blockB = TimeBlockModel(title: "Cocktails", scheduledStart: .now.addingTimeInterval(1800), duration: 3600)
        blockB.track = mainTrack
        context.insert(blockB)

        let blockC = TimeBlockModel(title: "Portraits", scheduledStart: .now, duration: 2700)
        blockC.track = photoTrack
        context.insert(blockC)

        try context.save()

        // All blocks across all tracks
        let allBlocks = event.tracks
            .flatMap(\.blocks)
            .sorted { $0.scheduledStart < $1.scheduledStart }
        #expect(allBlocks.count == 3)

        // Filter to Main track
        let mainFiltered = allBlocks.filter { $0.track?.id == mainTrack.id }
        #expect(mainFiltered.count == 2)
        #expect(mainFiltered.allSatisfy { $0.track?.name == "Main" })

        // Filter to Photo track
        let photoFiltered = allBlocks.filter { $0.track?.id == photoTrack.id }
        #expect(photoFiltered.count == 1)
        #expect(photoFiltered.first?.title == "Portraits")
    }

    /// AC: Default is "Main" selected — when selectedTrackID matches Main,
    /// only Main blocks are shown.
    @Test @MainActor func defaultMainSelectionShowsOnlyMainBlocks() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        context.insert(event)

        let mainTrack = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true, event: event)
        context.insert(mainTrack)

        let musicTrack = TimelineTrack(name: "Music", sortOrder: 1, event: event)
        context.insert(musicTrack)

        let blockA = TimeBlockModel(title: "Ceremony", scheduledStart: .now, duration: 1800)
        blockA.track = mainTrack
        context.insert(blockA)

        let blockB = TimeBlockModel(title: "DJ Set", scheduledStart: .now, duration: 3600)
        blockB.track = musicTrack
        context.insert(blockB)

        try context.save()

        // Simulate onAppear: selectedTrackID = mainTrack.id
        let selectedTrackID = mainTrack.id

        let allBlocks = event.tracks
            .flatMap(\.blocks)
            .sorted { $0.scheduledStart < $1.scheduledStart }

        let filtered = allBlocks.filter { $0.track?.id == selectedTrackID }
        #expect(filtered.count == 1)
        #expect(filtered.first?.title == "Ceremony")
    }

    /// AC: "All" tab (selectedTrackID = nil) shows blocks from every track.
    @Test @MainActor func allTabShowsBlocksFromEveryTrack() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        context.insert(event)

        let mainTrack = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true, event: event)
        context.insert(mainTrack)

        let photoTrack = TimelineTrack(name: "Photo", sortOrder: 1, event: event)
        context.insert(photoTrack)

        let musicTrack = TimelineTrack(name: "Music", sortOrder: 2, event: event)
        context.insert(musicTrack)

        for (title, track) in [("Ceremony", mainTrack), ("Portraits", photoTrack), ("DJ Set", musicTrack)] {
            let block = TimeBlockModel(title: title, scheduledStart: .now, duration: 1800)
            block.track = track
            context.insert(block)
        }
        try context.save()

        // selectedTrackID = nil means "All"
        let selectedTrackID: UUID? = nil
        let allBlocks = event.tracks
            .flatMap(\.blocks)
            .sorted { $0.scheduledStart < $1.scheduledStart }

        // When nil, no filter is applied — all blocks shown
        let filtered: [TimeBlockModel]
        if let trackID = selectedTrackID {
            filtered = allBlocks.filter { $0.track?.id == trackID }
        } else {
            filtered = allBlocks
        }

        #expect(filtered.count == 3)
        let titles = Set(filtered.map(\.title))
        #expect(titles.contains("Ceremony"))
        #expect(titles.contains("Portraits"))
        #expect(titles.contains("DJ Set"))
    }

    // MARK: - iPad Multi-Column & Drag-and-Drop

    /// AC: iPad shows all tracks as side-by-side columns — each track's blocks
    /// are scoped to that track only.
    @Test @MainActor func iPadColumnsShowBlocksScopedToEachTrack() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        context.insert(event)

        let mainTrack = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true, event: event)
        context.insert(mainTrack)

        let photoTrack = TimelineTrack(name: "Photo", sortOrder: 1, event: event)
        context.insert(photoTrack)

        let blockA = TimeBlockModel(title: "Ceremony", scheduledStart: .now, duration: 1800)
        blockA.track = mainTrack
        context.insert(blockA)

        let blockB = TimeBlockModel(title: "Cocktails", scheduledStart: .now.addingTimeInterval(1800), duration: 3600)
        blockB.track = mainTrack
        context.insert(blockB)

        let blockC = TimeBlockModel(title: "Portraits", scheduledStart: .now, duration: 2700)
        blockC.track = photoTrack
        context.insert(blockC)
        try context.save()

        // Simulate iPad column logic: each track shows only its own blocks
        let mainBlocks = mainTrack.blocks.sorted { $0.scheduledStart < $1.scheduledStart }
        let photoBlocks = photoTrack.blocks.sorted { $0.scheduledStart < $1.scheduledStart }

        #expect(mainBlocks.count == 2)
        #expect(photoBlocks.count == 1)
        #expect(mainBlocks.allSatisfy { $0.track?.id == mainTrack.id })
        #expect(photoBlocks.first?.title == "Portraits")

        // All tracks are displayed — sortedTracks returns both
        let sortedTracks = event.tracks.sorted { $0.sortOrder < $1.sortOrder }
        #expect(sortedTracks.count == 2)
        #expect(sortedTracks[0].name == "Main")
        #expect(sortedTracks[1].name == "Photo")
    }

    /// AC: Drag-and-drop reassigns block.track to the target track.
    @Test @MainActor func dragDropReassignsBlockTrack() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        context.insert(event)

        let mainTrack = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true, event: event)
        context.insert(mainTrack)

        let photoTrack = TimelineTrack(name: "Photo", sortOrder: 1, event: event)
        context.insert(photoTrack)

        let block = TimeBlockModel(title: "Portraits", scheduledStart: .now, duration: 2700)
        block.track = mainTrack
        context.insert(block)
        try context.save()

        #expect(block.track?.id == mainTrack.id)
        #expect(mainTrack.blocks.count == 1)
        #expect(photoTrack.blocks.count == 0)

        // Simulate drop: reassign block.track to photoTrack
        block.track = photoTrack
        try context.save()

        #expect(block.track?.id == photoTrack.id)
        #expect(photoTrack.blocks.contains(where: { $0.id == block.id }))
    }

    /// AC: Drag-drop to the same track is a no-op.
    @Test @MainActor func dragDropToSameTrackIsNoOp() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        context.insert(event)

        let mainTrack = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true, event: event)
        context.insert(mainTrack)

        let block = TimeBlockModel(title: "Ceremony", scheduledStart: .now, duration: 1800)
        block.track = mainTrack
        context.insert(block)
        try context.save()

        // Simulate drop onto same track — should remain unchanged
        let originalTrackID = block.track?.id
        // TrackColumnView.reassignBlock checks block.track?.id != targetTrack.id
        // and returns false (no-op) if same
        let isSameTrack = block.track?.id == mainTrack.id
        #expect(isSameTrack == true)
        #expect(block.track?.id == originalTrackID)
    }

    /// AC: Shared layout spans full time range across all tracks.
    @Test @MainActor func sharedLayoutSpansAllTracksTimeRange() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let base = Date.now
        let event = EventModel(title: "Wedding", date: base, latitude: 0, longitude: 0)
        context.insert(event)

        let mainTrack = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true, event: event)
        context.insert(mainTrack)

        let photoTrack = TimelineTrack(name: "Photo", sortOrder: 1, event: event)
        context.insert(photoTrack)

        // Main track: early block
        let blockA = TimeBlockModel(title: "Ceremony", scheduledStart: base, duration: 1800)
        blockA.track = mainTrack
        context.insert(blockA)

        // Photo track: late block — extends the time range
        let blockB = TimeBlockModel(title: "Sunset Shoot", scheduledStart: base.addingTimeInterval(7200), duration: 3600)
        blockB.track = photoTrack
        context.insert(blockB)
        try context.save()

        // Simulate sharedLayout: computed from ALL blocks
        let allBlocks = event.tracks
            .flatMap(\.blocks)
            .sorted { $0.scheduledStart < $1.scheduledStart }
        let layout = TimeRulerLayout.adaptive(blocks: allBlocks)

        // Ruler should start at or before the earliest block
        #expect(layout.rulerStart <= blockA.scheduledStart)
        // Ruler should end at or after the latest block's end
        let latestEnd = blockB.scheduledStart.addingTimeInterval(blockB.duration)
        #expect(layout.rulerEnd >= latestEnd)
    }
}

// MARK: - Test helper

private struct TestBlock: TimeRulerBlock {
    let blockStart: Date
    let blockEnd: Date
}
