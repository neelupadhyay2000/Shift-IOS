import Foundation
import Models
import Services
@testable import shiftTimeline
import SwiftData
import Testing

/// SHIFT-608: every repository write appends an `OutboxEntry`, stamped with a
/// monotonic `sequence` that preserves causal order (parents before children).
/// Payload integrity is sampled here and expanded in SHIFT-609.
@Suite("Outbox enqueue")
@MainActor
struct OutboxRepositoryTests {

    private let ownerID = UUID()

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

    // MARK: - Payload integrity (sampled; expanded in SHIFT-609)

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
}
