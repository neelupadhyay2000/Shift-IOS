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
        #expect(result.vendors.count == 2)
        #expect(Set(result.vendors.map(\.id)) == Set([vendor1.id, vendor2.id]))
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

        #expect(block.vendors.count == 1)

        // Simulate deselecting the vendor in inspector
        block.vendors = []
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TimeBlockModel>())
        let result = try #require(fetched.first)
        #expect(result.vendors.isEmpty)

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
        let eventVendors = event.vendors
        block.vendors = eventVendors.filter { selectedIDs.contains($0.id) }
        try context.save()

        #expect(block.vendors.count == 2)
        #expect(Set(block.vendors.map(\.name)) == Set(["Photographer", "Florist"]))
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
        #expect(result.dependencies.count == 2)
        #expect(Set(result.dependencies.map(\.title)) == Set(["Ceremony", "Cocktails"]))
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
        #expect(blockB.dependencies.count == 1)

        // Remove dependency
        blockB.dependencies = []
        try context.save()

        #expect(blockB.dependencies.isEmpty)
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
        let siblingBlocks = event.tracks
            .flatMap(\.blocks)
            .filter { $0.id != editingBlock.id }
            .sorted { $0.scheduledStart < $1.scheduledStart }

        let selectedIDs: Set<UUID> = [blocks[0].id, blocks[2].id]
        editingBlock.dependencies = siblingBlocks.filter { selectedIDs.contains($0.id) }
        try context.save()

        #expect(editingBlock.dependencies.count == 2)
        #expect(Set(editingBlock.dependencies.map(\.title)) == Set(["Block0", "Block2"]))
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
        #expect(result.vendors.count == 1)
        #expect(result.vendors.first?.name == "Jane")
        #expect(result.dependencies.count == 1)
        #expect(result.dependencies.first?.title == "Setup")
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
        #expect(fetched.first?.dependencies.isEmpty == true)
    }
}
