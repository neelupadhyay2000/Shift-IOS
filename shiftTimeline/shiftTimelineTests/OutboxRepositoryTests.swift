import Foundation
import Models
import Services
@testable import shiftTimeline
import SwiftData
import Testing

/// Every repository write appends an `OutboxEntry`, stamped with a
/// monotonic `sequence` that preserves causal order (parents before children).
/// Payload integrity is sampled here and expanded below.
@Suite("Outbox enqueue")
@MainActor
struct OutboxRepositoryTests {

    private let ownerID = UUID()

    /// Reference counter for the `onEnqueue` flush-trigger test.
    @MainActor private final class NudgeCounter { var count = 0 }

    private struct Stack {
        let container: ModelContainer
        let context: ModelContext
        let provider: OutboxRepositoryProvider
    }

    private func makeStack() throws -> Stack {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        // Deterministic queue inspection: persist only when the test says so.
        context.autosaveEnabled = false
        let owner = ownerID
        let provider = OutboxRepositoryProvider(
            context: context,
            local: SwiftDataRepositoryProvider(context: context),
            currentOwnerID: { owner }
        )
        return Stack(container: container, context: context, provider: provider)
    }

    private func outbox(_ context: ModelContext) throws -> [OutboxEntry] {
        try context.fetch(
            FetchDescriptor<OutboxEntry>(sortBy: [SortDescriptor(\.sequence)])
        )
    }

    // MARK: - Ordering / causality

    @Test("each aggregate insert enqueues an entry in causal (parent-first) order")
    func graphInsertEnqueuesInCausalOrder() async throws {
        let stack = try makeStack()
        let event = EventModel(title: "E", date: fixedTimestamp, latitude: 0, longitude: 0)
        let track = TimelineTrack(name: "Main", sortOrder: 0)
        let block = TimeBlockModel(title: "B", scheduledStart: fixedTimestamp, duration: 60)
        let vendor = VendorModel(name: "DJ", role: .dj)

        try await stack.provider.events.insert(event)
        try await stack.provider.tracks.insert(track, into: event)
        try await stack.provider.blocks.insert(block, into: track)
        try await stack.provider.vendors.insert(vendor, into: event)
        try stack.context.save()

        let entries = try outbox(stack.context)
        #expect(entries.map(\.tableName) == ["events", "tracks", "blocks", "event_vendors"])
        #expect(entries.map(\.rowID) == [event.id, track.id, block.id, vendor.id])
        #expect(entries.allSatisfy { $0.operation == "insert" })
        // Monotonic and gap-free across unsaved enqueues — the in-memory counter
        // does not depend on intermediate saves.
        #expect(entries.map(\.sequence) == [1, 2, 3, 4])
    }

    @Test("a track is always enqueued before the block that references it")
    func parentSequencePrecedesChild() async throws {
        let stack = try makeStack()
        let event = EventModel(title: "E", date: fixedTimestamp, latitude: 0, longitude: 0)
        let track = TimelineTrack(name: "Main", sortOrder: 0)
        let block = TimeBlockModel(title: "B", scheduledStart: fixedTimestamp, duration: 60)

        try await stack.provider.events.insert(event)
        try await stack.provider.tracks.insert(track, into: event)
        try await stack.provider.blocks.insert(block, into: track)
        try stack.context.save()

        let entries = try outbox(stack.context)
        let trackSeq = try #require(entries.first { $0.tableName == "tracks" }?.sequence)
        let blockSeq = try #require(entries.first { $0.tableName == "blocks" }?.sequence)
        #expect(trackSeq < blockSeq)
    }

    // MARK: - Payload integrity (sampled; expanded below.

    @Test("insert payloads are the row's DTO snapshot")
    func insertPayloadRoundTripsDTO() async throws {
        let stack = try makeStack()
        let event = EventModel(title: "Gala", date: fixedTimestamp, latitude: 1, longitude: 2)
        let track = TimelineTrack(name: "Main", sortOrder: 0)
        let block = TimeBlockModel(title: "Ceremony", scheduledStart: fixedTimestamp, duration: 1800)

        try await stack.provider.events.insert(event)
        try await stack.provider.tracks.insert(track, into: event)
        try await stack.provider.blocks.insert(block, into: track)
        try stack.context.save()

        let entries = try outbox(stack.context)

        let eventPayload = try #require(entries.first { $0.tableName == "events" }?.payload)
        let decodedEvent = try JSONDecoder().decode(EventDTO.self, from: eventPayload)
        #expect(decodedEvent == event.toDTO(ownerID: ownerID))

        let blockPayload = try #require(entries.first { $0.tableName == "blocks" }?.payload)
        let decodedBlock = try JSONDecoder().decode(BlockDTO.self, from: blockPayload)
        #expect(decodedBlock == block.toDTO(trackID: track.id, eventID: event.id))
    }

    // MARK: - Deletes

    @Test("delete enqueues a payload-less entry sequenced after the insert")
    func deleteEnqueuesTombstone() async throws {
        let stack = try makeStack()
        let event = EventModel(title: "E", date: fixedTimestamp, latitude: 0, longitude: 0)
        try await stack.provider.events.insert(event)
        try stack.context.save()
        try await stack.provider.events.delete(event)
        try stack.context.save()

        let entries = try outbox(stack.context)
        let insertSeq = try #require(entries.first { $0.operation == "insert" }?.sequence)
        let deleteEntry = try #require(entries.first { $0.operation == "delete" })
        #expect(deleteEntry.tableName == "events")
        #expect(deleteEntry.rowID == event.id)
        #expect(deleteEntry.payload == nil)
        #expect(deleteEntry.sequence > insertSeq)
    }

    // MARK: - Junctions

    @Test("vendor assignment enqueues a junction entry carrying the composite key")
    func assignmentEnqueuesJunctionAfterEndpoints() async throws {
        let stack = try makeStack()
        let event = EventModel(title: "E", date: fixedTimestamp, latitude: 0, longitude: 0)
        let track = TimelineTrack(name: "Main", sortOrder: 0)
        let block = TimeBlockModel(title: "B", scheduledStart: fixedTimestamp, duration: 60)
        let vendor = VendorModel(name: "DJ", role: .dj)

        try await stack.provider.events.insert(event)
        try await stack.provider.tracks.insert(track, into: event)
        try await stack.provider.blocks.insert(block, into: track)
        try await stack.provider.vendors.insert(vendor, into: event)
        try await stack.provider.vendors.assign(vendor, to: block)
        try stack.context.save()

        let entries = try outbox(stack.context)
        let junction = try #require(entries.first { $0.tableName == "block_vendors" })
        #expect(junction.operation == "insert")
        let dto = try JSONDecoder().decode(BlockVendorDTO.self, from: try #require(junction.payload))
        #expect(dto == BlockVendorDTO(blockID: block.id, eventVendorID: vendor.id, eventID: event.id))

        // The junction must follow both endpoints it references.
        let blockSeq = try #require(entries.first { $0.tableName == "blocks" }?.sequence)
        let vendorSeq = try #require(entries.first { $0.tableName == "event_vendors" }?.sequence)
        #expect(junction.sequence > blockSeq)
        #expect(junction.sequence > vendorSeq)
    }

    // MARK: - save(): in-place edits + bypass-inserts

    @Test("save() enqueues dirty edits and bypass-inserts, parent before child")
    func saveEnqueuesDirtyParentsFirst() async throws {
        let stack = try makeStack()
        let event = EventModel(title: "E", date: fixedTimestamp, latitude: 0, longitude: 0)
        let track = TimelineTrack(name: "Main", sortOrder: 0)
        try await stack.provider.events.insert(event)
        try await stack.provider.tracks.insert(track, into: event)
        try stack.context.save()
        let baseline = try outbox(stack.context).count

        // An in-place edit (no explicit op) and a bypass-insert (recordShift
        // inserts straight into the context) — both must be caught by save().
        event.title = "Renamed"
        PersistenceController.recordShift(
            deltaMinutes: 5, triggeredBy: .manual, event: event, into: stack.context
        )
        try await stack.provider.events.save()

        let new = Array(try outbox(stack.context).dropFirst(baseline))
        let eventIndex = try #require(new.firstIndex { $0.tableName == "events" })
        let shiftIndex = try #require(new.firstIndex { $0.tableName == "shift_records" })
        #expect(eventIndex < shiftIndex) // parent enqueued before child
        #expect(new.first { $0.tableName == "events" }?.operation == "update")
        #expect(new.first { $0.tableName == "shift_records" }?.operation == "insert")
    }

    // MARK: - Payload integrity per aggregate

    @Test("track and vendor insert payloads round-trip their DTOs")
    func trackAndVendorPayloadsRoundTrip() async throws {
        let stack = try makeStack()
        let event = EventModel(title: "E", date: fixedTimestamp, latitude: 0, longitude: 0)
        let track = TimelineTrack(name: "Main", sortOrder: 2, isDefault: true)
        let vendor = VendorModel(name: "DJ", role: .dj, phone: "555", email: "dj@x.com")

        try await stack.provider.events.insert(event)
        try await stack.provider.tracks.insert(track, into: event)
        try await stack.provider.vendors.insert(vendor, into: event)
        try stack.context.save()

        let entries = try outbox(stack.context)
        let trackPayload = try #require(entries.first { $0.tableName == "tracks" }?.payload)
        #expect(try JSONDecoder().decode(TrackDTO.self, from: trackPayload) == track.toDTO(eventID: event.id))

        let vendorPayload = try #require(entries.first { $0.tableName == "event_vendors" }?.payload)
        #expect(try JSONDecoder().decode(EventVendorDTO.self, from: vendorPayload) == vendor.toDTO(eventID: event.id))
    }

    @Test("shift record insert payload round-trips its DTO")
    func shiftRecordPayloadRoundTrips() async throws {
        let stack = try makeStack()
        let event = EventModel(title: "E", date: fixedTimestamp, latitude: 0, longitude: 0)
        let record = ShiftRecord(timestamp: fixedTimestamp, deltaMinutes: 10, triggeredBy: .manual)

        try await stack.provider.events.insert(event)
        try await stack.provider.shiftRecords.insert(record, into: event)
        try stack.context.save()

        let payload = try #require(try outbox(stack.context).first { $0.tableName == "shift_records" }?.payload)
        let decoded = try JSONDecoder().decode(ShiftRecordDTO.self, from: payload)
        #expect(decoded == record.toDTO(eventID: event.id, sourceBlockID: nil))
    }

    // MARK: - Op correctness — updates snapshot the latest value

    @Test("an edit enqueues an update whose payload snapshots the new value")
    func updatePayloadSnapshotsLatestValue() async throws {
        let stack = try makeStack()
        let event = EventModel(title: "Original", date: fixedTimestamp, latitude: 0, longitude: 0)
        try await stack.provider.events.insert(event)
        try stack.context.save()

        event.title = "Updated"
        try await stack.provider.events.save()

        let events = try outbox(stack.context).filter { $0.tableName == "events" }
        let insertEntry = try #require(events.first { $0.operation == "insert" })
        let updateEntry = try #require(events.first { $0.operation == "update" })

        // The insert payload is frozen at enqueue time…
        let insertDTO = try JSONDecoder().decode(EventDTO.self, from: try #require(insertEntry.payload))
        #expect(insertDTO.title == "Original")
        // …while the update payload reflects the edit, and the update follows the insert.
        let updateDTO = try JSONDecoder().decode(EventDTO.self, from: try #require(updateEntry.payload))
        #expect(updateDTO.title == "Updated")
        #expect(updateDTO == event.toDTO(ownerID: ownerID))
        #expect(updateEntry.sequence > insertEntry.sequence)
    }

    // MARK: - Junctions (dependency + deletes carry the composite key)

    @Test("a block dependency enqueues a block_dependencies entry with the composite key")
    func dependencyEnqueuesJunctionWithCompositeKey() async throws {
        let stack = try makeStack()
        let event = EventModel(title: "E", date: fixedTimestamp, latitude: 0, longitude: 0)
        let track = TimelineTrack(name: "Main", sortOrder: 0)
        let first = TimeBlockModel(title: "First", scheduledStart: fixedTimestamp, duration: 60)
        let second = TimeBlockModel(title: "Second", scheduledStart: fixedTimestamp, duration: 60)

        try await stack.provider.events.insert(event)
        try await stack.provider.tracks.insert(track, into: event)
        try await stack.provider.blocks.insert(first, into: track)
        try await stack.provider.blocks.insert(second, into: track)
        try await stack.provider.blocks.addDependency(second, to: first) // `first` depends on `second`
        try stack.context.save()

        let entries = try outbox(stack.context)
        let junction = try #require(entries.first { $0.tableName == "block_dependencies" })
        #expect(junction.operation == "insert")
        let dto = try JSONDecoder().decode(BlockDependencyDTO.self, from: try #require(junction.payload))
        #expect(dto == BlockDependencyDTO(blockID: first.id, dependsOnBlockID: second.id, eventID: event.id))

        // The edge follows both endpoint blocks.
        let firstSeq = try #require(entries.first { $0.tableName == "blocks" && $0.rowID == first.id }?.sequence)
        let secondSeq = try #require(entries.first { $0.tableName == "blocks" && $0.rowID == second.id }?.sequence)
        #expect(junction.sequence > firstSeq)
        #expect(junction.sequence > secondSeq)
    }

    @Test("unassign and removeDependency enqueue deletes that still carry the composite key")
    func junctionDeletesCarryCompositeKey() async throws {
        let stack = try makeStack()
        let event = EventModel(title: "E", date: fixedTimestamp, latitude: 0, longitude: 0)
        let track = TimelineTrack(name: "Main", sortOrder: 0)
        let block = TimeBlockModel(title: "B", scheduledStart: fixedTimestamp, duration: 60)
        let other = TimeBlockModel(title: "Dep", scheduledStart: fixedTimestamp, duration: 60)
        let vendor = VendorModel(name: "DJ", role: .dj)

        try await stack.provider.events.insert(event)
        try await stack.provider.tracks.insert(track, into: event)
        try await stack.provider.blocks.insert(block, into: track)
        try await stack.provider.blocks.insert(other, into: track)
        try await stack.provider.vendors.insert(vendor, into: event)
        try await stack.provider.vendors.assign(vendor, to: block)
        try await stack.provider.vendors.unassign(vendor, from: block)
        try await stack.provider.blocks.addDependency(other, to: block)
        try await stack.provider.blocks.removeDependency(other, from: block)
        try stack.context.save()

        let entries = try outbox(stack.context)

        // `.last` (highest sequence) for each junction table is the removal.
        let vendorDelete = try #require(entries.last { $0.tableName == "block_vendors" })
        #expect(vendorDelete.operation == "delete")
        let bvDTO = try JSONDecoder().decode(BlockVendorDTO.self, from: try #require(vendorDelete.payload))
        #expect(bvDTO == BlockVendorDTO(blockID: block.id, eventVendorID: vendor.id, eventID: event.id))

        let depDelete = try #require(entries.last { $0.tableName == "block_dependencies" })
        #expect(depDelete.operation == "delete")
        let bdDTO = try JSONDecoder().decode(BlockDependencyDTO.self, from: try #require(depDelete.payload))
        #expect(bdDTO == BlockDependencyDTO(blockID: block.id, dependsOnBlockID: other.id, eventID: event.id))
    }

    // MARK: - Stable FIFO order

    @Test("enqueued entries form a stable, gap-free FIFO order")
    func fifoOrderIsStableAndGapFree() async throws {
        let stack = try makeStack()
        let event = EventModel(title: "E", date: fixedTimestamp, latitude: 0, longitude: 0)
        let track = TimelineTrack(name: "Main", sortOrder: 0)
        let block = TimeBlockModel(title: "B", scheduledStart: fixedTimestamp, duration: 60)
        let vendor = VendorModel(name: "DJ", role: .dj)

        try await stack.provider.events.insert(event)
        try await stack.provider.tracks.insert(track, into: event)
        try await stack.provider.blocks.insert(block, into: track)
        try await stack.provider.vendors.insert(vendor, into: event)
        try await stack.provider.vendors.assign(vendor, to: block)
        try await stack.provider.vendors.delete(vendor)
        try stack.context.save()

        let entries = try outbox(stack.context)
        #expect(entries.count == 6)
        // Strictly increasing, gap-free, starting at 1 — a deterministic total order.
        #expect(entries.map(\.sequence) == Array(1...6))
        #expect(entries.map(\.tableName) == [
            "events", "tracks", "blocks", "event_vendors", "block_vendors", "event_vendors",
        ])
        #expect(entries.map(\.operation) == ["insert", "insert", "insert", "insert", "insert", "delete"])

        // Re-fetching yields the identical ordering: `sequence` is stable, not
        // dependent on `createdAt` ties or fetch timing.
        let refetched = try outbox(stack.context)
        #expect(refetched.map(\.rowID) == entries.map(\.rowID))
        #expect(refetched.map(\.operation) == entries.map(\.operation))
    }

    // MARK: - Flush trigger (post-write)

    @Test("each enqueued write nudges the flush trigger so writes push promptly")
    func enqueueNudgesFlushTrigger() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        context.autosaveEnabled = false
        let counter = NudgeCounter()
        let owner = ownerID
        let provider = OutboxRepositoryProvider(
            context: context,
            local: SwiftDataRepositoryProvider(context: context),
            currentOwnerID: { owner },
            onEnqueue: { counter.count += 1 }
        )

        let event = EventModel(title: "E", date: fixedTimestamp, latitude: 0, longitude: 0)
        try await provider.events.insert(event)
        #expect(counter.count == 1) // the insert nudged once

        let track = TimelineTrack(name: "Main", sortOrder: 0)
        try await provider.tracks.insert(track, into: event)
        #expect(counter.count == 2) // and again for the track

        // A delete also routes through the Outbox, so it nudges too.
        try await provider.events.delete(event)
        #expect(counter.count == 3)
    }
}
