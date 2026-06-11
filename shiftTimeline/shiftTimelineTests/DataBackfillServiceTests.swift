import Foundation
import Models
import Services
@testable import shiftTimeline
import SwiftData
import Testing

/// The one-time post-migration backfill enqueues the entire local
/// event graph into the Outbox as idempotent `insert` upserts, so a CloudKit-era
/// user's on-device data lands in Supabase the existing flush drains
/// it FIFO. These tests assert the *enqueue* contract: every owned row produces
/// exactly one id-keyed insert entry, parents precede children, junctions follow
/// their endpoints, and the event payload is stamped with the current owner.
@Suite("Data backfill enqueue")
@MainActor
struct DataBackfillServiceTests {

    private let ownerID = UUID()

    private struct Stack {
        let container: ModelContainer
        let context: ModelContext
        let local: SwiftDataRepositoryProvider
    }

    private func makeStack() throws -> Stack {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        // Deterministic queue inspection: persist only when the test says so, and
        // build the graph through the *local* provider so nothing is enqueued
        // until `backfill()` runs.
        context.autosaveEnabled = false
        return Stack(
            container: container,
            context: context,
            local: SwiftDataRepositoryProvider(context: context)
        )
    }

    private func outbox(_ context: ModelContext) throws -> [OutboxEntry] {
        try context.fetch(
            FetchDescriptor<OutboxEntry>(sortBy: [SortDescriptor(\.sequence)])
        )
    }

    private func service(_ stack: Stack, owner: UUID? = nil) -> DataBackfillService {
        let resolved = owner ?? ownerID
        return DataBackfillService(context: stack.context, currentOwnerID: { resolved })
    }

    /// Builds a representative single-event graph through the local provider:
    /// one track, two blocks, a vendor assigned to the first block, a dependency
    /// (B1 → B2), and a shift record. Returns the wired aggregates for assertions.
    @discardableResult
    private func seedGraph(_ stack: Stack) async throws -> (
        event: EventModel, track: TimelineTrack,
        b1: TimeBlockModel, b2: TimeBlockModel,
        vendor: VendorModel, record: ShiftRecord
    ) {
        let event = EventModel(title: "Gala", date: fixedTimestamp, latitude: 1, longitude: 2)
        let track = TimelineTrack(name: "Main", sortOrder: 0)
        let b1 = TimeBlockModel(title: "Ceremony", scheduledStart: fixedTimestamp, duration: 1800)
        let b2 = TimeBlockModel(title: "Reception", scheduledStart: fixedTimestamp, duration: 3600)
        let vendor = VendorModel(name: "DJ", role: .dj, phone: "555", email: "dj@x.com")
        let record = ShiftRecord(timestamp: fixedTimestamp, deltaMinutes: 10, triggeredBy: .manual)

        try await stack.local.events.insert(event)
        try await stack.local.tracks.insert(track, into: event)
        try await stack.local.blocks.insert(b1, into: track)
        try await stack.local.blocks.insert(b2, into: track)
        try await stack.local.vendors.insert(vendor, into: event)
        try await stack.local.vendors.assign(vendor, to: b1)
        try await stack.local.blocks.addDependency(b2, to: b1) // b1 depends on b2
        try await stack.local.shiftRecords.insert(record, into: event)
        try stack.context.save()

        return (event, track, b1, b2, vendor, record)
    }

    // MARK: - Full-graph enqueue

    @Test("backfill enqueues one insert entry per owned row, keyed by id")
    func enqueuesEveryRowAsInsert() async throws {
        let stack = try makeStack()
        let g = try await seedGraph(stack)

        let count = try service(stack).backfill()
        #expect(count == 1) // one event backed up

        let entries = try outbox(stack.context)
        #expect(entries.allSatisfy { $0.operation == "insert" })

        // One entry per row, keyed by the model id.
        func rowIDs(_ table: String) -> Set<UUID> {
            Set(entries.filter { $0.tableName == table }.map(\.rowID))
        }
        #expect(rowIDs("events") == [g.event.id])
        #expect(rowIDs("tracks") == [g.track.id])
        #expect(rowIDs("blocks") == [g.b1.id, g.b2.id])
        #expect(rowIDs("event_vendors") == [g.vendor.id])
        #expect(rowIDs("shift_records") == [g.record.id])
        // Junction entries are keyed by the owning block's id.
        #expect(rowIDs("block_vendors") == [g.b1.id])
        #expect(rowIDs("block_dependencies") == [g.b1.id])

        // No spurious extra entries.
        #expect(entries.count == 8)
    }

    @Test("parents are enqueued before children")
    func parentsPrecedeChildren() async throws {
        let stack = try makeStack()
        let g = try await seedGraph(stack)
        _ = try service(stack).backfill()

        let entries = try outbox(stack.context)
        func seq(_ table: String, _ id: UUID) throws -> Int {
            try #require(entries.first { $0.tableName == table && $0.rowID == id }?.sequence)
        }

        let eventSeq = try seq("events", g.event.id)
        let trackSeq = try seq("tracks", g.track.id)
        #expect(eventSeq < trackSeq)
        #expect(trackSeq < (try seq("blocks", g.b1.id)))
        #expect(trackSeq < (try seq("blocks", g.b2.id)))
        #expect(eventSeq < (try seq("event_vendors", g.vendor.id)))
        #expect(eventSeq < (try seq("shift_records", g.record.id)))
    }

    @Test("junctions are enqueued after both endpoints they reference")
    func junctionsFollowEndpoints() async throws {
        let stack = try makeStack()
        let g = try await seedGraph(stack)
        _ = try service(stack).backfill()

        let entries = try outbox(stack.context)
        let b1Seq = try #require(entries.first { $0.tableName == "blocks" && $0.rowID == g.b1.id }?.sequence)
        let b2Seq = try #require(entries.first { $0.tableName == "blocks" && $0.rowID == g.b2.id }?.sequence)
        let vendorSeq = try #require(entries.first { $0.tableName == "event_vendors" }?.sequence)

        let assignment = try #require(entries.first { $0.tableName == "block_vendors" })
        #expect(assignment.sequence > b1Seq)
        #expect(assignment.sequence > vendorSeq)
        let bvDTO = try JSONDecoder().decode(BlockVendorDTO.self, from: try #require(assignment.payload))
        #expect(bvDTO == BlockVendorDTO(blockID: g.b1.id, eventVendorID: g.vendor.id, eventID: g.event.id))

        let dependency = try #require(entries.first { $0.tableName == "block_dependencies" })
        #expect(dependency.sequence > b1Seq)
        #expect(dependency.sequence > b2Seq)
        let bdDTO = try JSONDecoder().decode(BlockDependencyDTO.self, from: try #require(dependency.payload))
        #expect(bdDTO == BlockDependencyDTO(blockID: g.b1.id, dependsOnBlockID: g.b2.id, eventID: g.event.id))
    }

    // MARK: - Owner stamping

    @Test("event payload is stamped with the current owner and the local row is claimed")
    func stampsCurrentOwner() async throws {
        let stack = try makeStack()
        let g = try await seedGraph(stack)
        #expect(g.event.ownerId == nil) // CloudKit-era row, never owned

        _ = try service(stack).backfill()

        // Local row is claimed for owner-vs-shared gating.
        #expect(g.event.ownerId == ownerID)

        // The enqueued payload carries owner_id = current profile.
        let payload = try #require(try outbox(stack.context).first { $0.tableName == "events" }?.payload)
        let dto = try JSONDecoder().decode(EventDTO.self, from: payload)
        #expect(dto.ownerID == ownerID)
        #expect(dto == g.event.toDTO(ownerID: ownerID))
    }

    // MARK: - Idempotency (id-keyed)

    @Test("re-running backfill re-enqueues the same id-keyed rows (upsert-safe, no new ids)")
    func reRunIsIdKeyed() async throws {
        let stack = try makeStack()
        let g = try await seedGraph(stack)

        _ = try service(stack).backfill()
        let firstIDs = Set(try outbox(stack.context).map(\.rowID))

        _ = try service(stack).backfill()
        let entries = try outbox(stack.context)

        // A second pass invents no new ids — every entry still targets an existing
        // row, so the id-keyed upsert on flush converges instead of duplicating.
        #expect(Set(entries.map(\.rowID)) == firstIDs)
        #expect(entries.allSatisfy { $0.operation == "insert" })
        #expect(entries.contains { $0.tableName == "events" && $0.rowID == g.event.id })
    }

    // MARK: - Ownership filtering

    @Test("events owned by a different profile are not backfilled")
    func skipsForeignOwnedEvents() async throws {
        let stack = try makeStack()
        let foreign = EventModel(title: "Shared-in", date: fixedTimestamp, latitude: 0, longitude: 0)
        foreign.ownerId = UUID() // owned by someone else (a shared-in event)
        try await stack.local.events.insert(foreign)
        try stack.context.save()

        let count = try service(stack).backfill()
        #expect(count == 0)
        #expect(try outbox(stack.context).isEmpty)
    }

    // MARK: - No signed-in owner

    @Test("backfill is a no-op when no profile is signed in")
    func noOpWithoutOwner() async throws {
        let stack = try makeStack()
        _ = try await seedGraph(stack)

        let count = try DataBackfillService(
            context: stack.context, currentOwnerID: { nil }
        ).backfill()

        #expect(count == 0)
        #expect(try outbox(stack.context).isEmpty)
    }

    @Test("backfill is a no-op with an empty store")
    func noOpWithEmptyStore() async throws {
        let stack = try makeStack()
        let count = try service(stack).backfill()
        #expect(count == 0)
        #expect(try outbox(stack.context).isEmpty)
    }
}
