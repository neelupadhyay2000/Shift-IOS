import Foundation
import Models
import Services
@testable import shiftTimeline
import Supabase
import SwiftData
import Testing

@Suite("RealtimeChangeApplier")
@MainActor
struct RealtimeChangeApplierTests {

    private struct Stack {
        let container: ModelContainer
        let context: ModelContext
        let applier: RealtimeChangeApplier
    }

    private func makeStack(suppressor: RealtimeEchoSuppressor? = nil) throws -> Stack {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let applier = RealtimeChangeApplier(context: context, echoSuppressor: suppressor)
        return Stack(container: container, context: context, applier: applier)
    }

    // MARK: - Fixtures

    private func eventDTO(id: UUID = UUID(), title: String = "Gala", deletedAt: PostgresTimestamp? = nil) -> EventDTO {
        EventDTO(id: id, ownerID: UUID(), title: title, date: fixedPGTimestamp, status: "planning", deletedAt: deletedAt)
    }

    private func trackDTO(id: UUID, eventID: UUID) -> TrackDTO {
        TrackDTO(id: id, eventID: eventID, name: "Main", sortOrder: 0, isDefault: true)
    }

    private func blockDTO(id: UUID, trackID: UUID, eventID: UUID) -> BlockDTO {
        BlockDTO(
            id: id, trackID: trackID, eventID: eventID, title: "Ceremony",
            scheduledStart: fixedPGTimestamp, originalStart: fixedPGTimestamp,
            duration: 1800, minimumDuration: 0, isPinned: false, notes: "",
            colorTag: "#007AFF", icon: "circle.fill", status: "upcoming",
            requiresReview: false, isOutdoor: false, venueAddress: "", venueName: "",
            isTransitBlock: false
        )
    }

    private func vendorDTO(id: UUID, eventID: UUID) -> EventVendorDTO {
        EventVendorDTO(id: id, eventID: eventID, displayName: "DJ", role: "dj", notificationThreshold: 600, hasAcknowledgedLatestShift: false)
    }

    private func upsert(_ table: String, _ dto: some Codable) throws -> RealtimeChange {
        .upsert(table: table, record: try JSONObject(dto))
    }

    private func events(in context: ModelContext) throws -> [EventModel] {
        try context.fetch(FetchDescriptor<EventModel>())
    }

    // MARK: - Insert / update / delete

    @Test("INSERT creates a model in the local store")
    func insertCreatesModel() throws {
        let stack = try makeStack()
        let id = UUID()
        try stack.applier.apply(upsert("events", eventDTO(id: id, title: "Wedding")))

        let all = try events(in: stack.context)
        #expect(all.count == 1)
        #expect(all.first?.id == id)
        #expect(all.first?.title == "Wedding")
    }

    @Test("UPDATE upserts the existing row by id, without duplicating")
    func updateModifiesExistingByID() throws {
        let stack = try makeStack()
        let id = UUID()
        try stack.applier.apply(upsert("events", eventDTO(id: id, title: "Old")))
        try stack.applier.apply(upsert("events", eventDTO(id: id, title: "New")))

        let all = try events(in: stack.context)
        #expect(all.count == 1)
        #expect(all.first?.title == "New")
    }

    @Test("DELETE removes the row addressed by its id")
    func deleteRemovesModel() throws {
        let stack = try makeStack()
        let id = UUID()
        try stack.applier.apply(upsert("events", eventDTO(id: id)))
        #expect(try events(in: stack.context).count == 1)

        try stack.applier.apply(.delete(table: "events", oldRecord: ["id": .string(id.uuidString)]))
        #expect(try events(in: stack.context).isEmpty)
    }

    @Test("an UPDATE carrying deleted_at is applied as a delete")
    func softDeleteRemovesRow() throws {
        let stack = try makeStack()
        let id = UUID()
        try stack.applier.apply(upsert("events", eventDTO(id: id)))
        #expect(try events(in: stack.context).count == 1)

        try stack.applier.apply(upsert("events", eventDTO(id: id, deletedAt: fixedPGTimestamp)))
        #expect(try events(in: stack.context).isEmpty)
    }

    // MARK: - Relationships

    @Test("a block INSERT wires to its parent track and event by id")
    func blockUpsertWiresParent() throws {
        let stack = try makeStack()
        let eventID = UUID(), trackID = UUID(), blockID = UUID()
        try stack.applier.apply(upsert("events", eventDTO(id: eventID)))
        try stack.applier.apply(upsert("tracks", trackDTO(id: trackID, eventID: eventID)))
        try stack.applier.apply(upsert("blocks", blockDTO(id: blockID, trackID: trackID, eventID: eventID)))

        let block = try #require(stack.context.fetch(FetchDescriptor<TimeBlockModel>()).first)
        #expect(block.id == blockID)
        #expect(block.track?.id == trackID)
        #expect(block.track?.event?.id == eventID)
    }

    @Test("block_vendors INSERT assigns and DELETE unassigns the vendor")
    func junctionAssignThenUnassign() throws {
        let stack = try makeStack()
        let eventID = UUID(), trackID = UUID(), blockID = UUID(), vendorID = UUID()
        try stack.applier.apply(upsert("events", eventDTO(id: eventID)))
        try stack.applier.apply(upsert("tracks", trackDTO(id: trackID, eventID: eventID)))
        try stack.applier.apply(upsert("blocks", blockDTO(id: blockID, trackID: trackID, eventID: eventID)))
        try stack.applier.apply(upsert("event_vendors", vendorDTO(id: vendorID, eventID: eventID)))

        try stack.applier.apply(upsert("block_vendors", BlockVendorDTO(blockID: blockID, eventVendorID: vendorID, eventID: eventID)))
        var block = try #require(stack.context.fetch(FetchDescriptor<TimeBlockModel>()).first { $0.id == blockID })
        #expect(block.vendors?.map(\.id) == [vendorID])

        try stack.applier.apply(.delete(
            table: "block_vendors",
            oldRecord: ["block_id": .string(blockID.uuidString), "event_vendor_id": .string(vendorID.uuidString)]
        ))
        block = try #require(stack.context.fetch(FetchDescriptor<TimeBlockModel>()).first { $0.id == blockID })
        #expect(block.vendors?.isEmpty ?? true)
    }

    /// A vendor's ack arrives as an `event_vendors` UPDATE; applying it
    /// flips `has_acknowledged_latest_shift` on the planner's local row (upsert by
    /// id, no duplicate), which is what drives the planner's ack grid live.
    @Test("event_vendors UPDATE flips has_acknowledged_latest_shift locally")
    func appliesVendorAckUpdate() throws {
        let stack = try makeStack()
        let vendorID = UUID(), eventID = UUID()

        // Vendor present, not yet acknowledged.
        try stack.applier.apply(upsert("event_vendors", vendorDTO(id: vendorID, eventID: eventID)))
        let initial = try #require(stack.context.fetch(FetchDescriptor<VendorModel>()).first)
        #expect(initial.hasAcknowledgedLatestShift == false)

        // Vendor acknowledges → realtime UPDATE with has_acknowledged_latest_shift = true.
        let acked = EventVendorDTO(
            id: vendorID, eventID: eventID, displayName: "DJ", role: "dj",
            notificationThreshold: 600, hasAcknowledgedLatestShift: true
        )
        try stack.applier.apply(upsert("event_vendors", acked))

        let vendors = try stack.context.fetch(FetchDescriptor<VendorModel>())
        #expect(vendors.count == 1, "Upsert by id — the ack must not create a duplicate row")
        #expect(vendors.first?.hasAcknowledgedLatestShift == true, "Planner's local vendor reflects the ack")
    }

    // MARK: - Stream loop

    @Test("the stream loop applies every change on the main actor")
    func streamLoopAppliesAll() async throws {
        let stack = try makeStack()
        let (stream, continuation) = AsyncStream<RealtimeChange>.makeStream()
        let recordA = try JSONObject(eventDTO(title: "A"))
        let recordB = try JSONObject(eventDTO(title: "B"))
        continuation.yield(.upsert(table: "events", record: recordA))
        continuation.yield(.upsert(table: "events", record: recordB))
        continuation.finish()

        await stack.applier.apply(stream)

        let titles = Set(try events(in: stack.context).map(\.title))
        #expect(titles == ["A", "B"])
    }

    // MARK: - Echo suppression

    @Test("a self-written row's echo is suppressed, not re-applied")
    func selfEchoIsSuppressed() throws {
        let suppressor = RealtimeEchoSuppressor()
        let stack = try makeStack(suppressor: suppressor)
        let id = UUID()
        suppressor.recordLocalWrite(table: "events", id: id)

        try stack.applier.apply(upsert("events", eventDTO(id: id, title: "Echo")))

        #expect(try events(in: stack.context).isEmpty)
    }

    @Test("a self-echo does not clobber a newer local edit")
    func selfEchoDoesNotClobberNewerLocalState() throws {
        let suppressor = RealtimeEchoSuppressor()
        let stack = try makeStack(suppressor: suppressor)
        let id = UUID()
        let local = EventModel(id: id, title: "Newer", date: fixedTimestamp, latitude: 0, longitude: 0)
        stack.context.insert(local)
        try stack.context.save()
        suppressor.recordLocalWrite(table: "events", id: id)

        // A stale echo of an earlier write arrives.
        try stack.applier.apply(upsert("events", eventDTO(id: id, title: "Older")))

        let event = try #require(try events(in: stack.context).first)
        #expect(event.title == "Newer")
    }

    @Test("a change from another device is applied normally")
    func nonSelfChangeIsApplied() throws {
        let suppressor = RealtimeEchoSuppressor()
        let stack = try makeStack(suppressor: suppressor)
        let id = UUID()
        // No recordLocalWrite — this is not our write.

        try stack.applier.apply(upsert("events", eventDTO(id: id, title: "FromPeer")))

        let event = try #require(try events(in: stack.context).first)
        #expect(event.title == "FromPeer")
    }
}
