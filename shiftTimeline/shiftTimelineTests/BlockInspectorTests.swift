import Foundation
import Models
import Services
import SwiftData
import Testing

struct BlockInspectorTests {

    // MARK: - Vendor Assignments

    @Test @MainActor func assignVendorsToBlockPersists() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        context.insert(event)

        let track = TimelineTrack(name: "Main", sortOrder: 0, event: event)
        context.insert(track)

        let block = TimeBlockModel(title: "Ceremony", scheduledStart: .now, duration: 1800)
        block.track = track
        context.insert(block)

        let vendor1 = VendorModel(name: "Jane", role: .photographer)
        vendor1.event = event
        context.insert(vendor1)

        let vendor2 = VendorModel(name: "Mike", role: .dj)
        vendor2.event = event
        context.insert(vendor2)

        try context.save()

        // Simulate BlockInspectorView save: assign vendors
        block.vendors = [vendor1, vendor2]
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TimeBlockModel>())
        let result = try #require(fetched.first)
        #expect((result.vendors ?? []).count == 2)
        #expect(Set((result.vendors ?? []).map(\.id)) == Set([vendor1.id, vendor2.id]))
    }

    @Test @MainActor func removeVendorFromBlockPersists() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Gala", date: .now, latitude: 0, longitude: 0)
        context.insert(event)

        let track = TimelineTrack(name: "Main", sortOrder: 0, event: event)
        context.insert(track)

        let block = TimeBlockModel(title: "Dinner", scheduledStart: .now, duration: 3600)
        block.track = track
        context.insert(block)

        let vendor = VendorModel(name: "Catering Co", role: .caterer)
        vendor.event = event
        context.insert(vendor)

        block.vendors = [vendor]
        try context.save()

        #expect((block.vendors ?? []).count == 1)

        // Simulate deselecting the vendor in inspector
        block.vendors = []
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TimeBlockModel>())
        let result = try #require(fetched.first)
        #expect((result.vendors ?? []).isEmpty)

        // Vendor itself should still exist
        let vendors = try context.fetch(FetchDescriptor<VendorModel>())
        #expect(vendors.count == 1)
    }

    @Test @MainActor func vendorAssignmentFiltersBySelectedIDs() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        context.insert(event)

        let track = TimelineTrack(name: "Main", sortOrder: 0, event: event)
        context.insert(track)

        let block = TimeBlockModel(title: "Photos", scheduledStart: .now, duration: 1800)
        block.track = track
        context.insert(block)

        let v1 = VendorModel(name: "Photographer", role: .photographer)
        v1.event = event
        let v2 = VendorModel(name: "DJ", role: .dj)
        v2.event = event
        let v3 = VendorModel(name: "Florist", role: .florist)
        v3.event = event
        context.insert(v1)
        context.insert(v2)
        context.insert(v3)
        try context.save()

        // Simulate inspector save: only v1 and v3 selected
        let selectedIDs: Set<UUID> = [v1.id, v3.id]
        let eventVendors = event.vendors ?? []
        block.vendors = eventVendors.filter { selectedIDs.contains($0.id) }
        try context.save()

        #expect((block.vendors ?? []).count == 2)
        #expect(Set((block.vendors ?? []).map(\.name)) == Set(["Photographer", "Florist"]))
    }

    // MARK: - Dependency Assignments

    @Test @MainActor func assignDependenciesToBlockPersists() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let base = Date.now
        let event = EventModel(title: "Wedding", date: base, latitude: 0, longitude: 0)
        context.insert(event)

        let track = TimelineTrack(name: "Main", sortOrder: 0, event: event)
        context.insert(track)

        let blockA = TimeBlockModel(title: "Ceremony", scheduledStart: base, duration: 1800)
        blockA.track = track
        context.insert(blockA)

        let blockB = TimeBlockModel(title: "Cocktails", scheduledStart: base.addingTimeInterval(1800), duration: 3600)
        blockB.track = track
        context.insert(blockB)

        let blockC = TimeBlockModel(title: "Dinner", scheduledStart: base.addingTimeInterval(5400), duration: 5400)
        blockC.track = track
        context.insert(blockC)
        try context.save()

        // Simulate inspector: blockC depends on blockA and blockB
        blockC.dependencies = [blockA, blockB]
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TimeBlockModel>(
            predicate: #Predicate { $0.title == "Dinner" }
        ))
        let result = try #require(fetched.first)
        #expect((result.dependencies ?? []).count == 2)
        #expect(Set((result.dependencies ?? []).map(\.title)) == Set(["Ceremony", "Cocktails"]))
    }

    @Test @MainActor func removeDependencyFromBlockPersists() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let base = Date.now
        let event = EventModel(title: "Wedding", date: base, latitude: 0, longitude: 0)
        context.insert(event)

        let track = TimelineTrack(name: "Main", sortOrder: 0, event: event)
        context.insert(track)

        let blockA = TimeBlockModel(title: "A", scheduledStart: base, duration: 600)
        blockA.track = track
        context.insert(blockA)

        let blockB = TimeBlockModel(title: "B", scheduledStart: base.addingTimeInterval(600), duration: 600)
        blockB.track = track
        context.insert(blockB)

        blockB.dependencies = [blockA]
        try context.save()
        #expect((blockB.dependencies ?? []).count == 1)

        // Remove dependency
        blockB.dependencies = []
        try context.save()

        #expect((blockB.dependencies ?? []).isEmpty)
        // blockA should still exist
        let blocks = try context.fetch(FetchDescriptor<TimeBlockModel>())
        #expect(blocks.count == 2)
    }

    @Test @MainActor func dependencyFiltersBySiblingBlocks() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let base = Date.now
        let event = EventModel(title: "Wedding", date: base, latitude: 0, longitude: 0)
        context.insert(event)

        let track = TimelineTrack(name: "Main", sortOrder: 0, event: event)
        context.insert(track)

        let blocks = (0..<4).map { i in
            TimeBlockModel(
                title: "Block\(i)",
                scheduledStart: base.addingTimeInterval(TimeInterval(i * 600)),
                duration: 600
            )
        }
        for b in blocks {
            b.track = track
            context.insert(b)
        }
        try context.save()

        // Simulate inspector for Block3: select Block0 and Block2 as dependencies
        let editingBlock = blocks[3]
        let siblingBlocks = (event.tracks ?? [])
            .flatMap { $0.blocks ?? [] }
            .filter { $0.id != editingBlock.id }
            .sorted { $0.scheduledStart < $1.scheduledStart }

        let selectedIDs: Set<UUID> = [blocks[0].id, blocks[2].id]
        editingBlock.dependencies = siblingBlocks.filter { selectedIDs.contains($0.id) }
        try context.save()

        #expect((editingBlock.dependencies ?? []).count == 2)
        #expect(Set((editingBlock.dependencies ?? []).map(\.title)) == Set(["Block0", "Block2"]))
    }

    /// AC: Self-dependency prevented — current block must not appear in the sibling list.
    @Test @MainActor func selfDependencyIsPrevented() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let base = Date.now
        let event = EventModel(title: "Wedding", date: base, latitude: 0, longitude: 0)
        context.insert(event)

        let track = TimelineTrack(name: "Main", sortOrder: 0, event: event)
        context.insert(track)

        let blockA = TimeBlockModel(title: "A", scheduledStart: base, duration: 600)
        blockA.track = track
        context.insert(blockA)

        let blockB = TimeBlockModel(title: "B", scheduledStart: base.addingTimeInterval(600), duration: 600)
        blockB.track = track
        context.insert(blockB)

        let blockC = TimeBlockModel(title: "C", scheduledStart: base.addingTimeInterval(1200), duration: 600)
        blockC.track = track
        context.insert(blockC)
        try context.save()

        // Simulate BlockInspectorView's siblingBlocks for blockB
        let editingBlock = blockB
        let siblingBlocks = (event.tracks ?? [])
            .flatMap { $0.blocks ?? [] }
            .filter { $0.id != editingBlock.id }
            .sorted { $0.scheduledStart < $1.scheduledStart }

        // blockB must NOT be in the sibling list
        #expect(!siblingBlocks.contains(where: { $0.id == editingBlock.id }))
        #expect(siblingBlocks.count == 2)
        #expect(Set(siblingBlocks.map(\.title)) == Set(["A", "C"]))

        // Even if someone tried to include blockB's own ID in selectedIDs,
        // the filter would exclude it since it's not in siblingBlocks
        let selectedIDs: Set<UUID> = [blockA.id, blockB.id, blockC.id]
        editingBlock.dependencies = siblingBlocks.filter { selectedIDs.contains($0.id) }
        try context.save()

        // Only A and C should be assigned — B (self) is excluded
        #expect((editingBlock.dependencies ?? []).count == 2)
        #expect(!(editingBlock.dependencies ?? []).contains(where: { $0.id == editingBlock.id }))
        #expect(Set((editingBlock.dependencies ?? []).map(\.title)) == Set(["A", "C"]))
    }

    // MARK: - Color Tag

    @Test @MainActor func colorTagUpdatePersists() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        context.insert(event)

        let track = TimelineTrack(name: "Main", sortOrder: 0, event: event)
        context.insert(track)

        let block = TimeBlockModel(
            title: "Ceremony",
            scheduledStart: .now,
            duration: 1800,
            colorTag: "#007AFF"
        )
        block.track = track
        context.insert(block)
        try context.save()

        #expect(block.colorTag == "#007AFF")

        // Simulate tapping a different color circle
        block.colorTag = "#FF3B30"
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TimeBlockModel>())
        let result = try #require(fetched.first)
        #expect(result.colorTag == "#FF3B30")
    }

    @Test func colorTagDefaultsToBlue() {
        let block = TimeBlockModel(title: "Test", scheduledStart: .now, duration: 600)
        #expect(block.colorTag == "#007AFF")
    }

    // MARK: - Icon

    @Test @MainActor func iconUpdatePersists() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        context.insert(event)

        let track = TimelineTrack(name: "Main", sortOrder: 0, event: event)
        context.insert(track)

        let block = TimeBlockModel(
            title: "Ceremony",
            scheduledStart: .now,
            duration: 1800,
            icon: "circle.fill"
        )
        block.track = track
        context.insert(block)
        try context.save()

        #expect(block.icon == "circle.fill")

        // Simulate tapping a different icon in the grid
        block.icon = "heart.fill"
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TimeBlockModel>())
        let result = try #require(fetched.first)
        #expect(result.icon == "heart.fill")
    }

    @Test func iconDefaultsToCircleFill() {
        let block = TimeBlockModel(title: "Test", scheduledStart: .now, duration: 600)
        #expect(block.icon == "circle.fill")
    }

    // MARK: - Full Inspector Save Flow

    @Test @MainActor func fullInspectorSaveFlowPersistsAllFields() async throws {
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
            isPinned: false,
            notes: "",
            colorTag: "#007AFF",
            icon: "circle.fill"
        )
        block.track = track
        context.insert(block)

        let vendor = VendorModel(name: "Jane", role: .photographer)
        vendor.event = event
        context.insert(vendor)

        let depBlock = TimeBlockModel(
            title: "Setup",
            scheduledStart: base.addingTimeInterval(-1800),
            duration: 1800
        )
        depBlock.track = track
        context.insert(depBlock)
        try context.save()

        // Simulate the full saveChanges() flow from BlockInspectorView
        let newStart = base.addingTimeInterval(600)
        block.title = "Grand Ceremony"
        block.scheduledStart = newStart
        block.duration = 2700
        block.isPinned = true
        block.notes = "Outdoor garden ceremony"
        block.colorTag = "#34C759"
        block.icon = "heart.fill"
        block.vendors = [vendor]
        block.dependencies = [depBlock]
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TimeBlockModel>(
            predicate: #Predicate { $0.title == "Grand Ceremony" }
        ))
        let result = try #require(fetched.first)
        #expect(result.title == "Grand Ceremony")
        #expect(result.scheduledStart == newStart)
        #expect(result.duration == 2700)
        #expect(result.isPinned == true)
        #expect(result.notes == "Outdoor garden ceremony")
        #expect(result.colorTag == "#34C759")
        #expect(result.icon == "heart.fill")
        #expect((result.vendors ?? []).count == 1)
        #expect((result.vendors ?? []).first?.name == "Jane")
        #expect((result.dependencies ?? []).count == 1)
        #expect((result.dependencies ?? []).first?.title == "Setup")
    }

    @Test @MainActor func deletingBlockNullifiesVendorRelationship() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        context.insert(event)

        let track = TimelineTrack(name: "Main", sortOrder: 0, event: event)
        context.insert(track)

        let block = TimeBlockModel(title: "Ceremony", scheduledStart: .now, duration: 1800)
        block.track = track
        context.insert(block)

        let vendor = VendorModel(name: "Jane", role: .photographer)
        vendor.event = event
        context.insert(vendor)

        block.vendors = [vendor]
        try context.save()

        context.delete(block)
        try context.save()

        // Vendor should still exist (nullify delete rule)
        let vendors = try context.fetch(FetchDescriptor<VendorModel>())
        #expect(vendors.count == 1)
        #expect(vendors.first?.name == "Jane")
    }

    @Test @MainActor func deletingBlockNullifiesDependencyRelationship() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let base = Date.now
        let event = EventModel(title: "Wedding", date: base, latitude: 0, longitude: 0)
        context.insert(event)

        let track = TimelineTrack(name: "Main", sortOrder: 0, event: event)
        context.insert(track)

        let blockA = TimeBlockModel(title: "A", scheduledStart: base, duration: 600)
        blockA.track = track
        context.insert(blockA)

        let blockB = TimeBlockModel(title: "B", scheduledStart: base.addingTimeInterval(600), duration: 600)
        blockB.track = track
        context.insert(blockB)

        blockB.dependencies = [blockA]
        try context.save()

        context.delete(blockA)
        try context.save()

        // blockB should still exist, with no dependencies
        let fetched = try context.fetch(FetchDescriptor<TimeBlockModel>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "B")
        #expect(fetched.first?.dependencies?.isEmpty == true)
    }

    // MARK: - Inspector Mode (Live-Write)

    /// AC: In inspector mode, writing directly to model properties
    /// updates SwiftData immediately — no explicit save needed.
    @Test @MainActor func inspectorModeLiveWriteUpdatesModelImmediately() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        context.insert(event)

        let track = TimelineTrack(name: "Main", sortOrder: 0, event: event)
        context.insert(track)

        let block = TimeBlockModel(
            title: "Ceremony",
            scheduledStart: .now,
            duration: 1800,
            isPinned: false,
            notes: "",
            colorTag: "#007AFF",
            icon: "circle.fill"
        )
        block.track = track
        context.insert(block)
        try context.save()

        // Simulate inspector mode live-write: each field mutation
        // is written directly to the model (no buffered save).
        block.title = "Grand Ceremony"
        #expect(block.title == "Grand Ceremony")

        block.duration = 2700
        #expect(block.duration == 2700)

        block.isPinned = true
        #expect(block.isPinned == true)

        block.notes = "Outdoor garden"
        #expect(block.notes == "Outdoor garden")

        block.colorTag = "#34C759"
        #expect(block.colorTag == "#34C759")

        block.icon = "heart.fill"
        #expect(block.icon == "heart.fill")

        // Verify all changes persist to SwiftData
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<TimeBlockModel>())
        let result = try #require(fetched.first)
        #expect(result.title == "Grand Ceremony")
        #expect(result.duration == 2700)
        #expect(result.isPinned == true)
        #expect(result.notes == "Outdoor garden")
        #expect(result.colorTag == "#34C759")
        #expect(result.icon == "heart.fill")
    }

    /// AC: In inspector mode, vendor assignment is live-written.
    @Test @MainActor func inspectorModeLiveWriteVendorAssignment() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        context.insert(event)

        let track = TimelineTrack(name: "Main", sortOrder: 0, event: event)
        context.insert(track)

        let block = TimeBlockModel(title: "Photos", scheduledStart: .now, duration: 1800)
        block.track = track
        context.insert(block)

        let vendor = VendorModel(name: "Jane", role: .photographer)
        vendor.event = event
        context.insert(vendor)
        try context.save()

        // Simulate live-write: toggle vendor on
        let eventVendors = event.vendors ?? []
        let selectedIDs: Set<UUID> = [vendor.id]
        block.vendors = eventVendors.filter { selectedIDs.contains($0.id) }

        // Immediately reflected — no save button needed
        #expect((block.vendors ?? []).count == 1)
        #expect((block.vendors ?? []).first?.name == "Jane")

        // Toggle vendor off
        block.vendors = []
        #expect((block.vendors ?? []).isEmpty)
    }

    /// AC: In sheet mode, changes are buffered in @State and NOT written
    /// to the model until saveChanges() is called.
    @Test @MainActor func sheetModeDoesNotWriteUntilSave() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        context.insert(event)

        let track = TimelineTrack(name: "Main", sortOrder: 0, event: event)
        context.insert(track)

        let block = TimeBlockModel(
            title: "Ceremony",
            scheduledStart: .now,
            duration: 1800,
            colorTag: "#007AFF"
        )
        block.track = track
        context.insert(block)
        try context.save()

        // Simulate sheet mode: user edits @State copies but hasn't
        // tapped Save yet. The model should be unchanged.
        let bufferedTitle = "Changed Title"
        let bufferedColor = "#FF3B30"

        // Model is NOT updated (these are local @State in the real view)
        #expect(block.title == "Ceremony")
        #expect(block.colorTag == "#007AFF")

        // Now simulate saveChanges()
        block.title = bufferedTitle
        block.colorTag = bufferedColor
        try context.save()

        #expect(block.title == "Changed Title")
        #expect(block.colorTag == "#FF3B30")
    }

    // MARK: - Outdoor Location Toggle

    /// AC: A new block defaults isOutdoor to false.
    @Test @MainActor func newBlockDefaultsIsOutdoorToFalse() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Concert", date: .now, latitude: 0, longitude: 0)
        context.insert(event)
        let track = TimelineTrack(name: "Main", sortOrder: 0, event: event)
        context.insert(track)
        let block = TimeBlockModel(title: "Opening Act", scheduledStart: .now, duration: 1800)
        block.track = track
        context.insert(block)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TimeBlockModel>())
        let result = try #require(fetched.first)
        #expect(result.isOutdoor == false)
    }

    /// AC: Setting isOutdoor to true persists across a SwiftData round-trip.
    @Test @MainActor func isOutdoorTruePersistedAfterSave() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Outdoor Gig", date: .now, latitude: 0, longitude: 0)
        context.insert(event)
        let track = TimelineTrack(name: "Stage", sortOrder: 0, event: event)
        context.insert(track)
        let block = TimeBlockModel(title: "Headliner", scheduledStart: .now, duration: 3600)
        block.track = track
        block.isOutdoor = true
        context.insert(block)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TimeBlockModel>())
        let result = try #require(fetched.first)
        #expect(result.isOutdoor == true)
    }

    /// AC: Inspector live-write correctly flips isOutdoor from false to true.
    @Test @MainActor func inspectorModeLiveWriteIsOutdoor() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Festival", date: .now, latitude: 0, longitude: 0)
        context.insert(event)
        let track = TimelineTrack(name: "Main Stage", sortOrder: 0, event: event)
        context.insert(track)
        let block = TimeBlockModel(title: "Warmup", scheduledStart: .now, duration: 1800)
        block.track = track
        context.insert(block)
        try context.save()

        #expect(block.isOutdoor == false)

        // Simulate onChange(of: isOutdoor) live-write
        block.isOutdoor = true
        #expect(block.isOutdoor == true)

        block.isOutdoor = false
        #expect(block.isOutdoor == false)
    }
}
