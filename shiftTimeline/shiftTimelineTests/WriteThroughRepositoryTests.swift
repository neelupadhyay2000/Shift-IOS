import Foundation
import Models
import Services
@testable import shiftTimeline
import SwiftData
import Testing

// MARK: - Recording remote spy

/// Records every remote call so write-through tests can assert that a mutation
/// reached the remote half (the local half is asserted against the real store).
@MainActor
final class RemoteSpy {
    var insertedEvents: [UUID] = []
    var deletedEvents: [UUID] = []
    var insertedTracks: [UUID] = []
    var insertedBlocks: [UUID] = []
    var insertedVendors: [UUID] = []
    var insertedShiftRecords: [UUID] = []
    var assigned: [(block: UUID, vendor: UUID)] = []
    var unassigned: [(block: UUID, vendor: UUID)] = []
    var addedDependencies: [(block: UUID, dependency: UUID)] = []
}

enum SpyRemoteError: Error { case boom }

@MainActor
private final class SpyEventRepository: EventRepositing {
    let spy: RemoteSpy
    var failInsert = false
    init(_ spy: RemoteSpy) { self.spy = spy }
    func insert(_ event: EventModel) async throws {
        if failInsert { throw SpyRemoteError.boom }
        spy.insertedEvents.append(event.id)
    }
    func fetch(id: UUID) async throws -> EventModel? { nil }
    func fetchAll() async throws -> [EventModel] { [] }
    func delete(_ event: EventModel) async throws { spy.deletedEvents.append(event.id) }
    func save() async throws {}
}

@MainActor
private final class SpyTrackRepository: TrackRepositing {
    let spy: RemoteSpy
    init(_ spy: RemoteSpy) { self.spy = spy }
    func insert(_ track: TimelineTrack, into event: EventModel) async throws { spy.insertedTracks.append(track.id) }
    func fetch(id: UUID) async throws -> TimelineTrack? { nil }
    func fetchAll(for event: EventModel) async throws -> [TimelineTrack] { [] }
    func delete(_ track: TimelineTrack) async throws {}
    func save() async throws {}
}

@MainActor
private final class SpyBlockRepository: BlockRepositing {
    let spy: RemoteSpy
    init(_ spy: RemoteSpy) { self.spy = spy }
    func insert(_ block: TimeBlockModel, into track: TimelineTrack) async throws { spy.insertedBlocks.append(block.id) }
    func fetch(id: UUID) async throws -> TimeBlockModel? { nil }
    func fetchAll(for track: TimelineTrack) async throws -> [TimeBlockModel] { [] }
    func delete(_ block: TimeBlockModel) async throws {}
    func save() async throws {}
    func addDependency(_ dependency: TimeBlockModel, to block: TimeBlockModel) async throws {
        spy.addedDependencies.append((block.id, dependency.id))
    }
    func removeDependency(_ dependency: TimeBlockModel, from block: TimeBlockModel) async throws {}
}

@MainActor
private final class SpyVendorRepository: VendorRepositing {
    let spy: RemoteSpy
    init(_ spy: RemoteSpy) { self.spy = spy }
    func insert(_ vendor: VendorModel, into event: EventModel) async throws { spy.insertedVendors.append(vendor.id) }
    func fetch(id: UUID) async throws -> VendorModel? { nil }
    func fetchAll(for event: EventModel) async throws -> [VendorModel] { [] }
    func delete(_ vendor: VendorModel) async throws {}
    func save() async throws {}
    func assign(_ vendor: VendorModel, to block: TimeBlockModel) async throws {
        spy.assigned.append((block.id, vendor.id))
    }
    func unassign(_ vendor: VendorModel, from block: TimeBlockModel) async throws {
        spy.unassigned.append((block.id, vendor.id))
    }
}

@MainActor
private final class SpyShiftRecordRepository: ShiftRecordRepositing {
    let spy: RemoteSpy
    init(_ spy: RemoteSpy) { self.spy = spy }
    func insert(_ record: ShiftRecord, into event: EventModel) async throws { spy.insertedShiftRecords.append(record.id) }
    func fetch(id: UUID) async throws -> ShiftRecord? { nil }
    func fetchAll(for event: EventModel) async throws -> [ShiftRecord] { [] }
    func delete(_ record: ShiftRecord) async throws {}
    func save() async throws {}
}

@MainActor
private struct SpyRepositoryProvider: RepositoryProviding {
    let events: any EventRepositing
    let tracks: any TrackRepositing
    let blocks: any BlockRepositing
    let vendors: any VendorRepositing
    let shiftRecords: any ShiftRecordRepositing
    init(spy: RemoteSpy, failEventInsert: Bool = false) {
        let eventRepo = SpyEventRepository(spy)
        eventRepo.failInsert = failEventInsert
        events = eventRepo
        tracks = SpyTrackRepository(spy)
        blocks = SpyBlockRepository(spy)
        vendors = SpyVendorRepository(spy)
        shiftRecords = SpyShiftRecordRepository(spy)
    }
}

// MARK: - Tests

@Suite("Write-through repositories")
@MainActor
struct WriteThroughRepositoryTests {

    private struct Stack {
        let container: ModelContainer
        let context: ModelContext
        let spy: RemoteSpy
        let provider: WriteThroughRepositoryProvider
    }

    private func makeStack() throws -> Stack {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        // Deterministic dirty-set capture in save() tests.
        context.autosaveEnabled = false
        let spy = RemoteSpy()
        let provider = WriteThroughRepositoryProvider(
            context: context,
            local: SwiftDataRepositoryProvider(context: context),
            remote: SpyRepositoryProvider(spy: spy)
        )
        return Stack(container: container, context: context, spy: spy, provider: provider)
    }

    @Test("insert persists to both the local cache and the remote")
    func insertWritesBoth() async throws {
        let stack = try makeStack()
        let event = EventModel(title: "Wedding", date: fixedTimestamp, latitude: 0, longitude: 0)

        try await stack.provider.events.insert(event)

        // Local: visible through the local-backed read path.
        #expect(try await stack.provider.events.fetch(id: event.id) != nil)
        // Remote: the spy recorded the insert.
        #expect(stack.spy.insertedEvents == [event.id])
    }

    @Test("the full aggregate graph inserts to both stores")
    func graphInsertsWriteBoth() async throws {
        let stack = try makeStack()
        let event = EventModel(title: "E", date: fixedTimestamp, latitude: 0, longitude: 0)
        let track = TimelineTrack(name: "Main", sortOrder: 0)
        let block = TimeBlockModel(title: "B", scheduledStart: fixedTimestamp, duration: 60)
        let vendor = VendorModel(name: "DJ", role: .dj)

        try await stack.provider.events.insert(event)
        try await stack.provider.tracks.insert(track, into: event)
        try await stack.provider.blocks.insert(block, into: track)
        try await stack.provider.vendors.insert(vendor, into: event)

        // Remote got each row.
        #expect(stack.spy.insertedEvents == [event.id])
        #expect(stack.spy.insertedTracks == [track.id])
        #expect(stack.spy.insertedBlocks == [block.id])
        #expect(stack.spy.insertedVendors == [vendor.id])
        // Local wired the graph.
        #expect(block.track?.id == track.id)
        #expect(track.event?.id == event.id)
    }

    @Test("delete removes from both stores")
    func deleteWritesBoth() async throws {
        let stack = try makeStack()
        let event = EventModel(title: "E", date: fixedTimestamp, latitude: 0, longitude: 0)
        try await stack.provider.events.insert(event)

        try await stack.provider.events.delete(event)

        #expect(try await stack.provider.events.fetch(id: event.id) == nil)
        #expect(stack.spy.deletedEvents == [event.id])
    }

    @Test("vendor assignment and block dependency write through to the remote junctions")
    func relationshipsWriteBoth() async throws {
        let stack = try makeStack()
        let event = EventModel(title: "E", date: fixedTimestamp, latitude: 0, longitude: 0)
        let track = TimelineTrack(name: "Main", sortOrder: 0)
        let block = TimeBlockModel(title: "B", scheduledStart: fixedTimestamp, duration: 60)
        let other = TimeBlockModel(title: "Setup", scheduledStart: fixedTimestamp, duration: 60)
        let vendor = VendorModel(name: "DJ", role: .dj)
        try await stack.provider.events.insert(event)
        try await stack.provider.tracks.insert(track, into: event)
        try await stack.provider.blocks.insert(block, into: track)
        try await stack.provider.blocks.insert(other, into: track)
        try await stack.provider.vendors.insert(vendor, into: event)

        try await stack.provider.vendors.assign(vendor, to: block)
        try await stack.provider.blocks.addDependency(other, to: block)

        // Local relationships set.
        #expect(block.vendors?.map(\.id) == [vendor.id])
        #expect(block.dependencies?.map(\.id) == [other.id])
        // Remote junctions recorded.
        #expect(stack.spy.assigned.contains { $0.block == block.id && $0.vendor == vendor.id })
        #expect(stack.spy.addedDependencies.contains { $0.block == block.id && $0.dependency == other.id })
    }

    @Test("save() mirrors an in-place edit to the remote")
    func saveMirrorsEdit() async throws {
        let stack = try makeStack()
        let event = EventModel(title: "Original", date: fixedTimestamp, latitude: 0, longitude: 0)
        try await stack.provider.events.insert(event)
        try await stack.provider.events.save() // event now clean locally

        event.title = "Edited"
        let before = stack.spy.insertedEvents.count
        try await stack.provider.events.save()

        // The edited row was re-upserted remotely by the coordinator.
        #expect(stack.spy.insertedEvents.count == before + 1)
        #expect(stack.spy.insertedEvents.last == event.id)
        // And the local edit is persisted.
        #expect(try await stack.provider.events.fetch(id: event.id)?.title == "Edited")
    }

    @Test("save() mirrors a row inserted straight into the context (e.g. recordShift)")
    func saveMirrorsBypassInsert() async throws {
        let stack = try makeStack()
        let event = EventModel(title: "E", date: fixedTimestamp, latitude: 0, longitude: 0)
        try await stack.provider.events.insert(event)
        try await stack.provider.events.save()

        // Insert a ShiftRecord directly into the context, bypassing the repository.
        let record = ShiftRecord(deltaMinutes: 10, triggeredBy: .manual)
        record.event = event
        stack.context.insert(record)

        try await stack.provider.shiftRecords.save()

        #expect(stack.spy.insertedShiftRecords.contains(record.id))
    }

    @Test("a remote write failure is recorded in diagnostics and never silently dropped")
    func remoteFailureRecorded() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        context.autosaveEnabled = false
        let suite = "shift.diagnostics.test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let diagnostics = SyncDiagnosticsCenter(defaults: defaults, storageKey: "events", maxEvents: 100)
        let provider = WriteThroughRepositoryProvider(
            context: context,
            local: SwiftDataRepositoryProvider(context: context),
            remote: SpyRepositoryProvider(spy: RemoteSpy(), failEventInsert: true),
            diagnostics: diagnostics
        )

        let event = EventModel(title: "Wedding", date: fixedTimestamp, latitude: 0, longitude: 0)
        // Local-first: this must NOT throw even though the remote write fails.
        try await provider.events.insert(event)

        // The local write still landed.
        #expect(try await provider.events.fetch(id: event.id) != nil)

        // The remote failure is recorded — visible, not silently dropped.
        let recorded = try #require(
            diagnostics.events.first { $0.name == "remoteWriteFailed" }
        )
        #expect(recorded.severity == .error)
        #expect(recorded.category == .push)
        #expect(recorded.params["op"] == "insert")
        #expect(recorded.params["table"] == "events")
        #expect(recorded.params["id"] == event.id.uuidString)
    }
}
