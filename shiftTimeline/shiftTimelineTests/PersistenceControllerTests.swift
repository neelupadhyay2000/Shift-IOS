import Foundation
import Models
import Services
import SwiftData
import Testing
@testable import shiftTimeline

/// Verifies `PersistenceController`'s local-only configuration.
/// All CloudKit mirror-state assertions have been removed; the suite
/// now asserts that:
///   - `forTesting()` produces an in-memory container with no CloudKit database.
///   - The schema registers all five model types.
///   - Basic CRUD persists correctly in the in-memory store.
@Suite("PersistenceController — local-only")
struct PersistenceControllerTests {

    // MARK: - forTesting() container

    @Test @MainActor func forTestingReturnsUsableContainer() throws {
        let container = try PersistenceController.forTesting()
        // Container must be usable — basic insert/fetch must succeed.
        let context = container.mainContext
        let event = EventModel(title: "Probe", date: .now, latitude: 0, longitude: 0)
        context.insert(event)
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<EventModel>())
        #expect(fetched.count == 1)
    }

    @Test @MainActor func forTestingIsInMemory() throws {
        let container = try PersistenceController.forTesting()
        // Every configuration must be flagged in-memory only.
        let allInMemory = container.configurations.allSatisfy { $0.isStoredInMemoryOnly }
        #expect(allInMemory)
    }

    @Test @MainActor func forTestingHasNoCloudKitDatabase() throws {
        let container = try PersistenceController.forTesting()
        // cloudKitContainerIdentifier is non-nil only when CloudKit is enabled.
        // Every configuration must have no CloudKit container.
        let anyCloudKit = container.configurations.contains {
            $0.cloudKitContainerIdentifier != nil
        }
        #expect(!anyCloudKit)
    }

    // MARK: - Schema completeness

    @Test func schemaContainsAllFiveModelTypes() {
        let schema = PersistenceController.schema
        let types = schema.entities.map { $0.name }
        #expect(types.contains("EventModel"))
        #expect(types.contains("TimeBlockModel"))
        #expect(types.contains("TimelineTrack"))
        #expect(types.contains("VendorModel"))
        #expect(types.contains("ShiftRecord"))
    }

    // MARK: - Basic persistence (insert → save → fetch round-trip)

    @Test @MainActor func eventModelPersistsInLocalStore() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Local Wedding", date: .now, latitude: 0, longitude: 0)
        context.insert(event)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<EventModel>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "Local Wedding")
    }

    @Test @MainActor func trackAndBlockPersistWithRelationships() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Concert", date: .now, latitude: 0, longitude: 0)
        context.insert(event)

        let track = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true, event: event)
        context.insert(track)

        let block = TimeBlockModel(title: "Soundcheck", scheduledStart: .now, duration: 1800)
        block.track = track
        context.insert(block)
        try context.save()

        let blocks = try context.fetch(FetchDescriptor<TimeBlockModel>())
        #expect(blocks.count == 1)
        #expect(blocks.first?.title == "Soundcheck")
        #expect(blocks.first?.track?.id == track.id)
    }

    @Test @MainActor func deleteEventCascadesToTracksAndBlocks() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "ToDelete", date: .now, latitude: 0, longitude: 0)
        context.insert(event)
        let track = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true, event: event)
        context.insert(track)
        let block = TimeBlockModel(title: "B", scheduledStart: .now, duration: 600)
        block.track = track
        context.insert(block)
        try context.save()

        context.delete(event)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<EventModel>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TimelineTrack>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TimeBlockModel>()).isEmpty)
    }

    // MARK: - recordShift helper

    @Test @MainActor func recordShiftInsertsShiftRecord() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Live Event", date: .now, latitude: 0, longitude: 0)
        context.insert(event)

        PersistenceController.recordShift(
            deltaMinutes: 10,
            triggeredBy: .manual,
            event: event,
            into: context
        )
        try context.save()

        let records = try context.fetch(FetchDescriptor<ShiftRecord>())
        #expect(records.count == 1)
        #expect(records.first?.deltaMinutes == 10)
        #expect(records.first?.triggeredBy == .manual)
        #expect(records.first?.event?.id == event.id)
    }
}
