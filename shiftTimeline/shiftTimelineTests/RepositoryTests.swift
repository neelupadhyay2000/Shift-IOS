import Foundation
import Models
import Services
import SwiftData
import Testing
@testable import shiftTimeline

// MARK: - EventRepository

@Suite("EventRepository")
struct EventRepositoryTests {

    // MARK: Create

    @Test @MainActor func insertRegistersEventAndFetchByIDReturnsIt() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let repo = SwiftDataEventRepository(context: context)

        let event = EventModel(title: "Summer Wedding", date: .now, latitude: 37.7, longitude: -122.4)
        try await repo.insert(event)

        let fetched = try await repo.fetch(id: event.id)
        let result = try #require(fetched)
        #expect(result.title == "Summer Wedding")
        #expect(result.id == event.id)
    }

    @Test @MainActor func insertMultipleEventsFetchAllReturnsAll() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let repo = SwiftDataEventRepository(context: context)

        let e1 = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        let e2 = EventModel(title: "Conference", date: .now, latitude: 0, longitude: 0)
        let e3 = EventModel(title: "Gala", date: .now, latitude: 0, longitude: 0)
        try await repo.insert(e1)
        try await repo.insert(e2)
        try await repo.insert(e3)
        try await repo.save()

        let all = try await repo.fetchAll()
        #expect(all.count == 3)
        let titles = Set(all.map(\.title))
        #expect(titles == ["Wedding", "Conference", "Gala"])
    }

    // MARK: Read

    @Test @MainActor func fetchByIDForUnknownIDReturnsNil() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let repo = SwiftDataEventRepository(context: context)

        let result = try await repo.fetch(id: UUID())
        #expect(result == nil)
    }

    @Test @MainActor func fetchByIDDistinguishesBetweenMultipleEvents() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let repo = SwiftDataEventRepository(context: context)

        let e1 = EventModel(title: "Alpha", date: .now, latitude: 0, longitude: 0)
        let e2 = EventModel(title: "Beta", date: .now, latitude: 0, longitude: 0)
        try await repo.insert(e1)
        try await repo.insert(e2)

        let result = try #require(try await repo.fetch(id: e2.id))
        #expect(result.title == "Beta")
    }

    // MARK: Delete

    @Test @MainActor func deleteRemovesEventFromFetch() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let repo = SwiftDataEventRepository(context: context)

        let event = EventModel(title: "ToDelete", date: .now, latitude: 0, longitude: 0)
        try await repo.insert(event)
        try await repo.save()

        try await repo.delete(event)
        try await repo.save()

        let result = try await repo.fetch(id: event.id)
        #expect(result == nil)
    }

    @Test @MainActor func deleteOneEventLeavesOtherIntact() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let repo = SwiftDataEventRepository(context: context)

        let keep = EventModel(title: "Keep", date: .now, latitude: 0, longitude: 0)
        let remove = EventModel(title: "Remove", date: .now, latitude: 0, longitude: 0)
        try await repo.insert(keep)
        try await repo.insert(remove)
        try await repo.save()

        try await repo.delete(remove)
        try await repo.save()

        let all = try await repo.fetchAll()
        #expect(all.count == 1)
        #expect(all.first?.title == "Keep")
    }

    // MARK: Save

    @Test @MainActor func saveFlushesContextWithoutThrowing() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let repo = SwiftDataEventRepository(context: context)

        let event = EventModel(title: "Flush", date: .now, latitude: 0, longitude: 0)
        try await repo.insert(event)
        try await repo.save()

        let all = try await repo.fetchAll()
        #expect(all.count == 1)
    }
}

// MARK: - TrackRepository

@Suite("TrackRepository")
struct TrackRepositoryTests {

    // MARK: Create + relationship wiring

    @Test @MainActor func insertWiresTrackToEvent() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let eventRepo = SwiftDataEventRepository(context: context)
        let trackRepo = SwiftDataTrackRepository(context: context)

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        try await eventRepo.insert(event)

        let track = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true)
        try await trackRepo.insert(track, into: event)

        #expect(track.event?.id == event.id)
        #expect((event.tracks ?? []).contains(where: { $0.id == track.id }))
    }

    // MARK: Read

    @Test @MainActor func fetchByIDReturnsTrack() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let eventRepo = SwiftDataEventRepository(context: context)
        let trackRepo = SwiftDataTrackRepository(context: context)

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        try await eventRepo.insert(event)

        let track = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true)
        try await trackRepo.insert(track, into: event)
        try await trackRepo.save()

        let result = try #require(try await trackRepo.fetch(id: track.id))
        #expect(result.name == "Main")
    }

    @Test @MainActor func fetchAllSortedBySortOrder() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let eventRepo = SwiftDataEventRepository(context: context)
        let trackRepo = SwiftDataTrackRepository(context: context)

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        try await eventRepo.insert(event)

        // Insert in reverse order
        let t2 = TimelineTrack(name: "Photo", sortOrder: 2)
        let t0 = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true)
        let t1 = TimelineTrack(name: "Music", sortOrder: 1)
        try await trackRepo.insert(t2, into: event)
        try await trackRepo.insert(t0, into: event)
        try await trackRepo.insert(t1, into: event)

        let sorted = try await trackRepo.fetchAll(for: event)
        #expect(sorted.count == 3)
        #expect(sorted[0].name == "Main")
        #expect(sorted[1].name == "Music")
        #expect(sorted[2].name == "Photo")
    }

    @Test @MainActor func fetchAllExcludesTracksFromOtherEvents() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let eventRepo = SwiftDataEventRepository(context: context)
        let trackRepo = SwiftDataTrackRepository(context: context)

        let event1 = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        let event2 = EventModel(title: "Gala", date: .now, latitude: 0, longitude: 0)
        try await eventRepo.insert(event1)
        try await eventRepo.insert(event2)

        let track1 = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true)
        let track2 = TimelineTrack(name: "Other", sortOrder: 0, isDefault: true)
        try await trackRepo.insert(track1, into: event1)
        try await trackRepo.insert(track2, into: event2)

        let forEvent1 = try await trackRepo.fetchAll(for: event1)
        #expect(forEvent1.count == 1)
        #expect(forEvent1.first?.id == track1.id)
    }

    // MARK: Delete

    @Test @MainActor func deleteRemovesTrackFromFetch() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let eventRepo = SwiftDataEventRepository(context: context)
        let trackRepo = SwiftDataTrackRepository(context: context)

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        try await eventRepo.insert(event)

        let track = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true)
        try await trackRepo.insert(track, into: event)
        try await trackRepo.save()

        try await trackRepo.delete(track)
        try await trackRepo.save()

        let result = try await trackRepo.fetch(id: track.id)
        #expect(result == nil)
    }
}

// MARK: - BlockRepository

@Suite("BlockRepository")
struct BlockRepositoryTests {

    // MARK: Create + relationship wiring

    @Test @MainActor func insertWiresBlockToTrack() async throws {
        let container = try PersistenceController.forTesting()
        let (event, track, blockRepo) = try await makeEventAndTrack(container: container)

        let block = TimeBlockModel(title: "Ceremony", scheduledStart: .now, duration: 1800)
        try await blockRepo.insert(block, into: track)

        #expect(block.track?.id == track.id)
        #expect((track.blocks ?? []).contains(where: { $0.id == block.id }))
        _ = event
    }

    // MARK: Read

    @Test @MainActor func fetchByIDReturnsBlock() async throws {
        let container = try PersistenceController.forTesting()
        let (_, track, blockRepo) = try await makeEventAndTrack(container: container)

        let block = TimeBlockModel(title: "Dinner", scheduledStart: .now, duration: 5400)
        try await blockRepo.insert(block, into: track)
        try await blockRepo.save()

        let result = try #require(try await blockRepo.fetch(id: block.id))
        #expect(result.title == "Dinner")
        #expect(result.duration == 5400)
    }

    @Test @MainActor func fetchAllSortedByScheduledStart() async throws {
        let container = try PersistenceController.forTesting()
        let (_, track, blockRepo) = try await makeEventAndTrack(container: container)

        let base = Date.now
        // Insert in reverse chronological order
        let b3 = TimeBlockModel(title: "C", scheduledStart: base.addingTimeInterval(7200), duration: 1800)
        let b1 = TimeBlockModel(title: "A", scheduledStart: base, duration: 1800)
        let b2 = TimeBlockModel(title: "B", scheduledStart: base.addingTimeInterval(3600), duration: 1800)
        try await blockRepo.insert(b3, into: track)
        try await blockRepo.insert(b1, into: track)
        try await blockRepo.insert(b2, into: track)

        let sorted = try await blockRepo.fetchAll(for: track)
        #expect(sorted.count == 3)
        #expect(sorted[0].title == "A")
        #expect(sorted[1].title == "B")
        #expect(sorted[2].title == "C")
    }

    @Test @MainActor func fetchAllExcludesBlocksFromOtherTracks() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let eventRepo = SwiftDataEventRepository(context: context)
        let trackRepo = SwiftDataTrackRepository(context: context)
        let blockRepo = SwiftDataBlockRepository(context: context)

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        try await eventRepo.insert(event)
        let track1 = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true)
        let track2 = TimelineTrack(name: "Photo", sortOrder: 1)
        try await trackRepo.insert(track1, into: event)
        try await trackRepo.insert(track2, into: event)

        let b1 = TimeBlockModel(title: "Ceremony", scheduledStart: .now, duration: 1800)
        let b2 = TimeBlockModel(title: "Portraits", scheduledStart: .now, duration: 2700)
        try await blockRepo.insert(b1, into: track1)
        try await blockRepo.insert(b2, into: track2)

        let forTrack1 = try await blockRepo.fetchAll(for: track1)
        #expect(forTrack1.count == 1)
        #expect(forTrack1.first?.title == "Ceremony")
    }

    // MARK: Delete

    @Test @MainActor func deleteRemovesBlockFromFetch() async throws {
        let container = try PersistenceController.forTesting()
        let (_, track, blockRepo) = try await makeEventAndTrack(container: container)

        let block = TimeBlockModel(title: "ToDelete", scheduledStart: .now, duration: 600)
        try await blockRepo.insert(block, into: track)
        try await blockRepo.save()

        try await blockRepo.delete(block)
        try await blockRepo.save()

        let result = try await blockRepo.fetch(id: block.id)
        #expect(result == nil)
    }

    // MARK: Dependency relationships

    @Test @MainActor func addDependencyLinksBlocks() async throws {
        let container = try PersistenceController.forTesting()
        let (_, track, blockRepo) = try await makeEventAndTrack(container: container)

        let base = Date.now
        let blockA = TimeBlockModel(title: "A", scheduledStart: base, duration: 1800)
        let blockB = TimeBlockModel(title: "B", scheduledStart: base.addingTimeInterval(1800), duration: 1800)
        try await blockRepo.insert(blockA, into: track)
        try await blockRepo.insert(blockB, into: track)

        try await blockRepo.addDependency(blockA, to: blockB)

        #expect((blockB.dependencies ?? []).contains(where: { $0.id == blockA.id }))
    }

    @Test @MainActor func addDependencyIsIdempotent() async throws {
        let container = try PersistenceController.forTesting()
        let (_, track, blockRepo) = try await makeEventAndTrack(container: container)

        let base = Date.now
        let dep = TimeBlockModel(title: "Dep", scheduledStart: base, duration: 600)
        let block = TimeBlockModel(title: "Block", scheduledStart: base.addingTimeInterval(600), duration: 600)
        try await blockRepo.insert(dep, into: track)
        try await blockRepo.insert(block, into: track)

        try await blockRepo.addDependency(dep, to: block)
        try await blockRepo.addDependency(dep, to: block)  // second call must be no-op

        let deps = block.dependencies ?? []
        #expect(deps.filter { $0.id == dep.id }.count == 1)
    }

    @Test @MainActor func removeDependencyUnlinksBlock() async throws {
        let container = try PersistenceController.forTesting()
        let (_, track, blockRepo) = try await makeEventAndTrack(container: container)

        let base = Date.now
        let dep = TimeBlockModel(title: "Dep", scheduledStart: base, duration: 600)
        let block = TimeBlockModel(title: "Block", scheduledStart: base.addingTimeInterval(600), duration: 600)
        try await blockRepo.insert(dep, into: track)
        try await blockRepo.insert(block, into: track)

        try await blockRepo.addDependency(dep, to: block)
        #expect((block.dependencies ?? []).contains(where: { $0.id == dep.id }))

        try await blockRepo.removeDependency(dep, from: block)
        #expect(!(block.dependencies ?? []).contains(where: { $0.id == dep.id }))
    }

    // MARK: - Helpers

    @MainActor
    private func makeEventAndTrack(
        container: ModelContainer
    ) async throws -> (EventModel, TimelineTrack, SwiftDataBlockRepository) {
        let context = container.mainContext
        let eventRepo = SwiftDataEventRepository(context: context)
        let trackRepo = SwiftDataTrackRepository(context: context)
        let blockRepo = SwiftDataBlockRepository(context: context)

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        try await eventRepo.insert(event)

        let track = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true)
        try await trackRepo.insert(track, into: event)

        return (event, track, blockRepo)
    }
}

// MARK: - VendorRepository

@Suite("VendorRepository")
struct VendorRepositoryTests {

    // MARK: Create + relationship wiring

    @Test @MainActor func insertWiresVendorToEvent() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let eventRepo = SwiftDataEventRepository(context: context)
        let vendorRepo = SwiftDataVendorRepository(context: context)

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        try await eventRepo.insert(event)

        let vendor = VendorModel(name: "Jane", role: .photographer)
        try await vendorRepo.insert(vendor, into: event)

        #expect(vendor.event?.id == event.id)
        #expect((event.vendors ?? []).contains(where: { $0.id == vendor.id }))
    }

    // MARK: Read

    @Test @MainActor func fetchByIDReturnsVendor() async throws {
        let container = try PersistenceController.forTesting()
        let (event, vendorRepo) = try await makeEventAndVendorRepo(container: container)

        let vendor = VendorModel(name: "DJ Mike", role: .dj, email: "mike@example.com")
        try await vendorRepo.insert(vendor, into: event)
        try await vendorRepo.save()

        let result = try #require(try await vendorRepo.fetch(id: vendor.id))
        #expect(result.name == "DJ Mike")
        #expect(result.role == .dj)
    }

    @Test @MainActor func fetchAllReturnsAllVendorsForEvent() async throws {
        let container = try PersistenceController.forTesting()
        let (event, vendorRepo) = try await makeEventAndVendorRepo(container: container)

        let v1 = VendorModel(name: "Alice", role: .photographer)
        let v2 = VendorModel(name: "Bob", role: .dj)
        let v3 = VendorModel(name: "Carol", role: .caterer)
        try await vendorRepo.insert(v1, into: event)
        try await vendorRepo.insert(v2, into: event)
        try await vendorRepo.insert(v3, into: event)
        try await vendorRepo.save()

        let all = try await vendorRepo.fetchAll(for: event)
        #expect(all.count == 3)
        #expect(Set(all.map(\.name)) == ["Alice", "Bob", "Carol"])
    }

    @Test @MainActor func fetchAllExcludesVendorsFromOtherEvents() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let eventRepo = SwiftDataEventRepository(context: context)
        let vendorRepo = SwiftDataVendorRepository(context: context)

        let event1 = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        let event2 = EventModel(title: "Gala", date: .now, latitude: 0, longitude: 0)
        try await eventRepo.insert(event1)
        try await eventRepo.insert(event2)

        let v1 = VendorModel(name: "ForEvent1", role: .photographer)
        let v2 = VendorModel(name: "ForEvent2", role: .dj)
        try await vendorRepo.insert(v1, into: event1)
        try await vendorRepo.insert(v2, into: event2)

        let forEvent1 = try await vendorRepo.fetchAll(for: event1)
        #expect(forEvent1.count == 1)
        #expect(forEvent1.first?.name == "ForEvent1")
    }

    // MARK: Delete

    @Test @MainActor func deleteRemovesVendorFromFetch() async throws {
        let container = try PersistenceController.forTesting()
        let (event, vendorRepo) = try await makeEventAndVendorRepo(container: container)

        let vendor = VendorModel(name: "ToDelete", role: .custom)
        try await vendorRepo.insert(vendor, into: event)
        try await vendorRepo.save()

        try await vendorRepo.delete(vendor)
        try await vendorRepo.save()

        let result = try await vendorRepo.fetch(id: vendor.id)
        #expect(result == nil)
    }

    // MARK: Block-assignment relationships

    @Test @MainActor func assignAddsVendorToBlockAssignedList() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let eventRepo = SwiftDataEventRepository(context: context)
        let trackRepo = SwiftDataTrackRepository(context: context)
        let blockRepo = SwiftDataBlockRepository(context: context)
        let vendorRepo = SwiftDataVendorRepository(context: context)

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        try await eventRepo.insert(event)
        let track = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true)
        try await trackRepo.insert(track, into: event)
        let block = TimeBlockModel(title: "Ceremony", scheduledStart: .now, duration: 1800)
        try await blockRepo.insert(block, into: track)
        let vendor = VendorModel(name: "Photographer", role: .photographer)
        try await vendorRepo.insert(vendor, into: event)

        try await vendorRepo.assign(vendor, to: block)

        #expect((block.vendors ?? []).contains(where: { $0.id == vendor.id }))
    }

    @Test @MainActor func assignIsIdempotent() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let eventRepo = SwiftDataEventRepository(context: context)
        let trackRepo = SwiftDataTrackRepository(context: context)
        let blockRepo = SwiftDataBlockRepository(context: context)
        let vendorRepo = SwiftDataVendorRepository(context: context)

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        try await eventRepo.insert(event)
        let track = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true)
        try await trackRepo.insert(track, into: event)
        let block = TimeBlockModel(title: "Ceremony", scheduledStart: .now, duration: 1800)
        try await blockRepo.insert(block, into: track)
        let vendor = VendorModel(name: "Photographer", role: .photographer)
        try await vendorRepo.insert(vendor, into: event)

        try await vendorRepo.assign(vendor, to: block)
        try await vendorRepo.assign(vendor, to: block)  // second call must be no-op

        let assigned = block.vendors ?? []
        #expect(assigned.filter { $0.id == vendor.id }.count == 1)
    }

    @Test @MainActor func unassignRemovesVendorFromBlock() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let eventRepo = SwiftDataEventRepository(context: context)
        let trackRepo = SwiftDataTrackRepository(context: context)
        let blockRepo = SwiftDataBlockRepository(context: context)
        let vendorRepo = SwiftDataVendorRepository(context: context)

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        try await eventRepo.insert(event)
        let track = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true)
        try await trackRepo.insert(track, into: event)
        let block = TimeBlockModel(title: "Ceremony", scheduledStart: .now, duration: 1800)
        try await blockRepo.insert(block, into: track)
        let vendor = VendorModel(name: "Photographer", role: .photographer)
        try await vendorRepo.insert(vendor, into: event)

        try await vendorRepo.assign(vendor, to: block)
        #expect((block.vendors ?? []).contains(where: { $0.id == vendor.id }))

        try await vendorRepo.unassign(vendor, from: block)
        #expect(!(block.vendors ?? []).contains(where: { $0.id == vendor.id }))
    }

    @Test @MainActor func unassignOneVendorLeavesOtherAssigned() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let eventRepo = SwiftDataEventRepository(context: context)
        let trackRepo = SwiftDataTrackRepository(context: context)
        let blockRepo = SwiftDataBlockRepository(context: context)
        let vendorRepo = SwiftDataVendorRepository(context: context)

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        try await eventRepo.insert(event)
        let track = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true)
        try await trackRepo.insert(track, into: event)
        let block = TimeBlockModel(title: "Ceremony", scheduledStart: .now, duration: 1800)
        try await blockRepo.insert(block, into: track)
        let v1 = VendorModel(name: "Photographer", role: .photographer)
        let v2 = VendorModel(name: "Florist", role: .florist)
        try await vendorRepo.insert(v1, into: event)
        try await vendorRepo.insert(v2, into: event)

        try await vendorRepo.assign(v1, to: block)
        try await vendorRepo.assign(v2, to: block)
        try await vendorRepo.unassign(v1, from: block)

        let assigned = block.vendors ?? []
        #expect(assigned.count == 1)
        #expect(assigned.first?.id == v2.id)
    }

    // MARK: - Helpers

    @MainActor
    private func makeEventAndVendorRepo(
        container: ModelContainer
    ) async throws -> (EventModel, SwiftDataVendorRepository) {
        let context = container.mainContext
        let eventRepo = SwiftDataEventRepository(context: context)
        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        try await eventRepo.insert(event)
        return (event, SwiftDataVendorRepository(context: context))
    }
}

// MARK: - ShiftRecordRepository

@Suite("ShiftRecordRepository")
struct ShiftRecordRepositoryTests {

    // MARK: Create + relationship wiring

    @Test @MainActor func insertWiresRecordToEvent() async throws {
        let container = try PersistenceController.forTesting()
        let (event, recordRepo) = try await makeEventAndRecordRepo(container: container)

        let record = ShiftRecord(deltaMinutes: 15, triggeredBy: .manual)
        try await recordRepo.insert(record, into: event)

        #expect(record.event?.id == event.id)
        #expect((event.shiftRecords ?? []).contains(where: { $0.id == record.id }))
    }

    @Test @MainActor func insertPreservesSourceBlockRelationship() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let eventRepo = SwiftDataEventRepository(context: context)
        let trackRepo = SwiftDataTrackRepository(context: context)
        let blockRepo = SwiftDataBlockRepository(context: context)
        let recordRepo = SwiftDataShiftRecordRepository(context: context)

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        try await eventRepo.insert(event)
        let track = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true)
        try await trackRepo.insert(track, into: event)
        let block = TimeBlockModel(title: "Ceremony", scheduledStart: .now, duration: 1800)
        try await blockRepo.insert(block, into: track)

        let record = ShiftRecord(deltaMinutes: 10, triggeredBy: .manual, sourceBlock: block)
        try await recordRepo.insert(record, into: event)

        #expect(record.sourceBlock?.id == block.id)
        #expect(record.event?.id == event.id)
    }

    // MARK: Read

    @Test @MainActor func fetchByIDReturnsRecord() async throws {
        let container = try PersistenceController.forTesting()
        let (event, recordRepo) = try await makeEventAndRecordRepo(container: container)

        let record = ShiftRecord(deltaMinutes: 5, triggeredBy: .dependency)
        try await recordRepo.insert(record, into: event)
        try await recordRepo.save()

        let result = try #require(try await recordRepo.fetch(id: record.id))
        #expect(result.deltaMinutes == 5)
        #expect(result.triggeredBy == .dependency)
    }

    @Test @MainActor func fetchAllSortedByTimestamp() async throws {
        let container = try PersistenceController.forTesting()
        let (event, recordRepo) = try await makeEventAndRecordRepo(container: container)

        let base = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let r3 = ShiftRecord(timestamp: base.addingTimeInterval(200), deltaMinutes: 3, triggeredBy: .manual)
        let r1 = ShiftRecord(timestamp: base,                          deltaMinutes: 1, triggeredBy: .manual)
        let r2 = ShiftRecord(timestamp: base.addingTimeInterval(100),  deltaMinutes: 2, triggeredBy: .watch)
        try await recordRepo.insert(r3, into: event)
        try await recordRepo.insert(r1, into: event)
        try await recordRepo.insert(r2, into: event)

        let sorted = try await recordRepo.fetchAll(for: event)
        #expect(sorted.count == 3)
        #expect(sorted[0].deltaMinutes == 1)
        #expect(sorted[1].deltaMinutes == 2)
        #expect(sorted[2].deltaMinutes == 3)
    }

    @Test @MainActor func fetchAllExcludesRecordsFromOtherEvents() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let eventRepo = SwiftDataEventRepository(context: context)
        let recordRepo = SwiftDataShiftRecordRepository(context: context)

        let event1 = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        let event2 = EventModel(title: "Gala", date: .now, latitude: 0, longitude: 0)
        try await eventRepo.insert(event1)
        try await eventRepo.insert(event2)

        let r1 = ShiftRecord(deltaMinutes: 10, triggeredBy: .manual)
        let r2 = ShiftRecord(deltaMinutes: 20, triggeredBy: .manual)
        try await recordRepo.insert(r1, into: event1)
        try await recordRepo.insert(r2, into: event2)

        let forEvent1 = try await recordRepo.fetchAll(for: event1)
        #expect(forEvent1.count == 1)
        #expect(forEvent1.first?.id == r1.id)
    }

    // MARK: Delete

    @Test @MainActor func deleteRemovesRecordFromFetch() async throws {
        let container = try PersistenceController.forTesting()
        let (event, recordRepo) = try await makeEventAndRecordRepo(container: container)

        let record = ShiftRecord(deltaMinutes: 5, triggeredBy: .undo)
        try await recordRepo.insert(record, into: event)
        try await recordRepo.save()

        try await recordRepo.delete(record)
        try await recordRepo.save()

        let result = try await recordRepo.fetch(id: record.id)
        #expect(result == nil)
    }

    @Test @MainActor func deleteOneRecordLeavesOthersIntact() async throws {
        let container = try PersistenceController.forTesting()
        let (event, recordRepo) = try await makeEventAndRecordRepo(container: container)

        let keep   = ShiftRecord(deltaMinutes: 5,  triggeredBy: .manual)
        let remove = ShiftRecord(deltaMinutes: 15, triggeredBy: .watch)
        try await recordRepo.insert(keep,   into: event)
        try await recordRepo.insert(remove, into: event)
        try await recordRepo.save()

        try await recordRepo.delete(remove)
        try await recordRepo.save()

        let all = try await recordRepo.fetchAll(for: event)
        #expect(all.count == 1)
        #expect(all.first?.id == keep.id)
    }

    // MARK: - Helpers

    @MainActor
    private func makeEventAndRecordRepo(
        container: ModelContainer
    ) async throws -> (EventModel, SwiftDataShiftRecordRepository) {
        let context = container.mainContext
        let eventRepo = SwiftDataEventRepository(context: context)
        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        try await eventRepo.insert(event)
        return (event, SwiftDataShiftRecordRepository(context: context))
    }
}
