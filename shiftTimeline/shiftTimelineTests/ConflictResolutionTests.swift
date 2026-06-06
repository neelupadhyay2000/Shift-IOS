import Foundation
import Models
import Services
@testable import shiftTimeline
import SwiftData
import Supabase
import Testing

/// SHIFT-605 conflict resolution. Timeline rows are planner-authoritative (only
/// the owner can write them — enforced server-side by RLS); between the owner's
/// own devices, the apply layer resolves last-write-wins by server `updated_at`,
/// so a stale remote change never clobbers a newer local version regardless of
/// arrival order (SHIFT-615). Vendor acknowledgment is the same row-level LWW,
/// with echo/origin handling so a vendor ack and a planner edit never ping-pong
/// (SHIFT-616). The convergence suite proves concurrent edits land on identical
/// state across devices under every apply order (SHIFT-617).
@Suite("Conflict resolution — LWW & convergence")
@MainActor
struct ConflictResolutionTests {

    private let t0 = Date(timeIntervalSince1970: 1_770_000_000)
    private let t1 = Date(timeIntervalSince1970: 1_780_000_000)
    private let t2 = Date(timeIntervalSince1970: 1_790_000_000)
    private let t3 = Date(timeIntervalSince1970: 1_800_000_000)

    /// Holds the container so it isn't deallocated mid-test (a dropped
    /// `ModelContainer` tears down the store and `context.fetch` then traps).
    private struct Stack {
        let container: ModelContainer
        let context: ModelContext
        let applier: RealtimeChangeApplier
    }

    private func makeStack(echoSuppressor: RealtimeEchoSuppressor? = nil) throws -> Stack {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        return Stack(
            container: container,
            context: context,
            applier: RealtimeChangeApplier(context: context, echoSuppressor: echoSuppressor)
        )
    }

    private func eventChange(id: UUID, title: String, updatedAt: Date?, deletedAt: Date? = nil) throws -> RealtimeChange {
        let dto = EventDTO(
            id: id, ownerID: UUID(), title: title, date: PostgresTimestamp(t1),
            status: "planning", updatedAt: PostgresTimestamp(updatedAt), deletedAt: PostgresTimestamp(deletedAt)
        )
        return .upsert(table: "events", record: try JSONObject(dto))
    }

    private func trackChange(id: UUID, eventID: UUID, name: String, updatedAt: Date) throws -> RealtimeChange {
        let dto = TrackDTO(
            id: id, eventID: eventID, name: name, sortOrder: 0, isDefault: false,
            updatedAt: PostgresTimestamp(updatedAt)
        )
        return .upsert(table: "tracks", record: try JSONObject(dto))
    }

    private func blockChange(id: UUID, trackID: UUID, eventID: UUID, title: String, updatedAt: Date) throws -> RealtimeChange {
        let dto = BlockDTO(
            id: id, trackID: trackID, eventID: eventID, title: title,
            scheduledStart: PostgresTimestamp(t1), originalStart: PostgresTimestamp(t1),
            duration: 60, minimumDuration: 0, isPinned: false, notes: "",
            colorTag: "#007AFF", icon: "circle.fill", status: "upcoming",
            requiresReview: false, isOutdoor: false, venueAddress: "", venueName: "",
            isTransitBlock: false, updatedAt: PostgresTimestamp(updatedAt)
        )
        return .upsert(table: "blocks", record: try JSONObject(dto))
    }

    private func vendorChange(id: UUID, eventID: UUID, acknowledged: Bool, updatedAt: Date) throws -> RealtimeChange {
        let dto = EventVendorDTO(
            id: id, eventID: eventID, displayName: "DJ", role: "dj",
            notificationThreshold: 600, hasAcknowledgedLatestShift: acknowledged,
            updatedAt: PostgresTimestamp(updatedAt)
        )
        return .upsert(table: "event_vendors", record: try JSONObject(dto))
    }

    private func event(_ context: ModelContext) throws -> EventModel? {
        try context.fetch(FetchDescriptor<EventModel>()).first
    }

    private func vendor(_ context: ModelContext) throws -> VendorModel? {
        try context.fetch(FetchDescriptor<VendorModel>()).first
    }

    /// A value snapshot of a device's converged state — the fields LWW resolves.
    private struct DeviceState: Equatable {
        let eventTitles: [UUID: String]
        let blockTitles: [UUID: String]
        let vendorAcks: [UUID: Bool]
    }

    private func snapshot(_ context: ModelContext) throws -> DeviceState {
        DeviceState(
            eventTitles: Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<EventModel>()).map { ($0.id, $0.title) }),
            blockTitles: Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<TimeBlockModel>()).map { ($0.id, $0.title) }),
            vendorAcks: Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<VendorModel>()).map { ($0.id, $0.hasAcknowledgedLatestShift) })
        )
    }

    /// One device: applies the causal `setup` (parents-before-children creation,
    /// as realtime/delta always deliver), then the `concurrent` edits in the
    /// given order. Returns the converged state.
    private func device(setup: [RealtimeChange], concurrent: [RealtimeChange]) throws -> DeviceState {
        let stack = try makeStack()
        for change in setup + concurrent {
            try stack.applier.apply(change)
        }
        return try snapshot(stack.context)
    }

    // MARK: - LWW

    @Test("a newer remote version applies")
    func newerRemoteApplies() throws {
        let stack = try makeStack()
        let id = UUID()
        try stack.applier.apply(eventChange(id: id, title: "v1", updatedAt: t1))
        try stack.applier.apply(eventChange(id: id, title: "v2", updatedAt: t2))

        let event = try #require(try event(stack.context))
        #expect(event.title == "v2")
        #expect(event.updatedAt == t2)
    }

    @Test("a stale remote version (older updated_at) is skipped, not applied out of order")
    func staleRemoteIsSkipped() throws {
        let stack = try makeStack()
        let id = UUID()
        try stack.applier.apply(eventChange(id: id, title: "v2", updatedAt: t2)) // newer arrives first
        try stack.applier.apply(eventChange(id: id, title: "v1", updatedAt: t1)) // older arrives late

        let event = try #require(try event(stack.context))
        #expect(event.title == "v2") // not clobbered by the stale write
        #expect(event.updatedAt == t2)
    }

    @Test("an equal-version re-delivery doesn't clobber a local edit on that version")
    func equalVersionSkipProtectsLocalEdit() throws {
        let stack = try makeStack()
        let id = UUID()
        try stack.applier.apply(eventChange(id: id, title: "server", updatedAt: t1))

        // The owner edits locally on top of the t1 version (updatedAt stays t1).
        let local = try #require(try event(stack.context))
        local.title = "local edit"

        // A re-delivery of the same (t1) version arrives.
        try stack.applier.apply(eventChange(id: id, title: "server", updatedAt: t1))

        #expect(try event(stack.context)?.title == "local edit")
    }

    @Test("a remote version applies onto a local row that has no server time yet")
    func appliesOntoLocallyCreatedRow() throws {
        let stack = try makeStack()
        let id = UUID()
        stack.context.insert(EventModel(id: id, title: "local", date: t1, latitude: 0, longitude: 0)) // updatedAt nil
        try stack.context.save()

        try stack.applier.apply(eventChange(id: id, title: "server", updatedAt: t1))

        let event = try #require(try event(stack.context))
        #expect(event.title == "server")
        #expect(event.updatedAt == t1)
    }

    @Test("LWW guards the whole timeline — a stale block update is skipped")
    func staleBlockUpdateIsSkipped() throws {
        let stack = try makeStack()
        let eventID = UUID(), trackID = UUID(), blockID = UUID()
        try stack.applier.apply(eventChange(id: eventID, title: "E", updatedAt: t1))
        try stack.applier.apply(trackChange(id: trackID, eventID: eventID, name: "Main", updatedAt: t1))
        try stack.applier.apply(blockChange(id: blockID, trackID: trackID, eventID: eventID, title: "v2", updatedAt: t2))
        try stack.applier.apply(blockChange(id: blockID, trackID: trackID, eventID: eventID, title: "v1", updatedAt: t1)) // stale

        let block = try #require(try stack.context.fetch(FetchDescriptor<TimeBlockModel>()).first)
        #expect(block.title == "v2")
        #expect(block.updatedAt == t2)
    }

    // MARK: - Vendor acknowledgment LWW (SHIFT-616)

    @Test("a vendor's newer ack wins over an older version")
    func vendorNewerAckWins() throws {
        let stack = try makeStack()
        let vendorID = UUID(), eventID = UUID()
        try stack.applier.apply(vendorChange(id: vendorID, eventID: eventID, acknowledged: false, updatedAt: t1))
        try stack.applier.apply(vendorChange(id: vendorID, eventID: eventID, acknowledged: true, updatedAt: t2))

        let vendor = try #require(try vendor(stack.context))
        #expect(vendor.hasAcknowledgedLatestShift == true)
        #expect(vendor.updatedAt == t2)
    }

    @Test("a stale ack can't clobber a newer reset (no ping-pong)")
    func staleAckDoesNotClobberNewerReset() throws {
        let stack = try makeStack()
        let vendorID = UUID(), eventID = UUID()
        // Planner reset (ack=false) at the newer t2 arrives first…
        try stack.applier.apply(vendorChange(id: vendorID, eventID: eventID, acknowledged: false, updatedAt: t2))
        // …then the vendor's older ack (ack=true) at t1 arrives late.
        try stack.applier.apply(vendorChange(id: vendorID, eventID: eventID, acknowledged: true, updatedAt: t1))

        let vendor = try #require(try vendor(stack.context))
        #expect(vendor.hasAcknowledgedLatestShift == false) // newer reset stands
        #expect(vendor.updatedAt == t2)
    }

    // MARK: - Echo / origin handling (SHIFT-616)

    @Test("a vendor's own write echo is suppressed even if newer (origin handling)")
    func vendorSelfEchoSuppressed() throws {
        let suppressor = RealtimeEchoSuppressor()
        let stack = try makeStack(echoSuppressor: suppressor)
        let vendorID = UUID(), eventID = UUID()
        // Local ack state at t1.
        try stack.applier.apply(vendorChange(id: vendorID, eventID: eventID, acknowledged: true, updatedAt: t1))
        // This device just wrote that row (its ack).
        suppressor.recordLocalWrite(table: "event_vendors", id: vendorID)

        // Its own echo comes back with a NEWER updated_at — LWW alone would apply
        // it, but origin handling recognizes the self-write and skips it, so it
        // can't ping-pong over local state.
        try stack.applier.apply(vendorChange(id: vendorID, eventID: eventID, acknowledged: false, updatedAt: t3))

        let vendor = try #require(try vendor(stack.context))
        #expect(vendor.hasAcknowledgedLatestShift == true) // echo suppressed
    }

    @Test("a planner change to a row this device didn't write still applies")
    func plannerChangeAppliesWhenNotSelfWritten() throws {
        let suppressor = RealtimeEchoSuppressor()
        let stack = try makeStack(echoSuppressor: suppressor)
        let vendorID = UUID(), eventID = UUID()
        try stack.applier.apply(vendorChange(id: vendorID, eventID: eventID, acknowledged: true, updatedAt: t1))
        // No recordLocalWrite for this row — a genuine peer change must apply.
        try stack.applier.apply(vendorChange(id: vendorID, eventID: eventID, acknowledged: false, updatedAt: t2))

        #expect(try vendor(stack.context)?.hasAcknowledgedLatestShift == false)
    }

    // MARK: - Multi-device convergence (SHIFT-617)

    @Test("concurrent edits to the same event converge regardless of apply order")
    func concurrentEventEditsConverge() throws {
        let id = UUID()
        let setup = [try eventChange(id: id, title: "init", updatedAt: t0)]
        let concurrent = [
            try eventChange(id: id, title: "deviceA", updatedAt: t1),
            try eventChange(id: id, title: "deviceB", updatedAt: t2),
        ]

        let a = try device(setup: setup, concurrent: concurrent)
        let b = try device(setup: setup, concurrent: Array(concurrent.reversed()))

        #expect(a.eventTitles[id] == "deviceB") // highest updated_at wins
        #expect(a == b)
    }

    @Test("a concurrent vendor ack and planner reset converge on both devices")
    func concurrentVendorAckConverges() throws {
        let vendorID = UUID(), eventID = UUID()
        let setup = [try vendorChange(id: vendorID, eventID: eventID, acknowledged: false, updatedAt: t0)]
        let concurrent = [
            try vendorChange(id: vendorID, eventID: eventID, acknowledged: true, updatedAt: t2),  // vendor acks
            try vendorChange(id: vendorID, eventID: eventID, acknowledged: false, updatedAt: t1), // planner reset (older)
        ]

        let a = try device(setup: setup, concurrent: concurrent)
        let b = try device(setup: setup, concurrent: Array(concurrent.reversed()))

        #expect(a.vendorAcks[vendorID] == true) // the t2 ack wins
        #expect(a == b)
    }

    @Test("concurrent edits across the whole graph converge identically under three orderings")
    func multiRowConcurrentEditsConvergeAcrossOrderings() throws {
        let eventID = UUID(), trackID = UUID(), blockID = UUID(), vendorID = UUID()
        // Causal creation (parents before children) — as realtime/delta deliver.
        let setup = [
            try eventChange(id: eventID, title: "init", updatedAt: t0),
            try trackChange(id: trackID, eventID: eventID, name: "init", updatedAt: t0),
            try blockChange(id: blockID, trackID: trackID, eventID: eventID, title: "init", updatedAt: t0),
            try vendorChange(id: vendorID, eventID: eventID, acknowledged: false, updatedAt: t0),
        ]
        // Concurrent edits from multiple devices, interleaved with stale ones.
        let concurrent = [
            try eventChange(id: eventID, title: "E2", updatedAt: t2),
            try blockChange(id: blockID, trackID: trackID, eventID: eventID, title: "B3", updatedAt: t3),
            try vendorChange(id: vendorID, eventID: eventID, acknowledged: true, updatedAt: t2),
            try eventChange(id: eventID, title: "E1", updatedAt: t1), // stale
            try blockChange(id: blockID, trackID: trackID, eventID: eventID, title: "B1", updatedAt: t1), // stale
        ]

        let forward = try device(setup: setup, concurrent: concurrent)
        let reversed = try device(setup: setup, concurrent: Array(concurrent.reversed()))
        let scrambled = try device(setup: setup, concurrent: [
            concurrent[3], concurrent[1], concurrent[4], concurrent[0], concurrent[2],
        ])

        // Correct: each row converges to its highest-updated_at version.
        #expect(forward.eventTitles[eventID] == "E2")
        #expect(forward.blockTitles[blockID] == "B3")
        #expect(forward.vendorAcks[vendorID] == true)
        // Convergent: every apply order lands on the same state.
        #expect(forward == reversed)
        #expect(forward == scrambled)
    }

    // MARK: - Soft-delete / tombstones (SHIFT-618)

    @Test("a tombstone deletes the local row")
    func tombstoneDeletesLocalRow() throws {
        let stack = try makeStack()
        let id = UUID()
        try stack.applier.apply(eventChange(id: id, title: "live", updatedAt: t1))
        try stack.applier.apply(eventChange(id: id, title: "live", updatedAt: t2, deletedAt: t2))

        #expect(try event(stack.context) == nil)
    }

    @Test("a stale tombstone is skipped — a newer edit survives the delete")
    func staleTombstoneSkipped() throws {
        let stack = try makeStack()
        let id = UUID()
        try stack.applier.apply(eventChange(id: id, title: "edited", updatedAt: t2)) // newer edit
        try stack.applier.apply(eventChange(id: id, title: "x", updatedAt: t1, deletedAt: t1)) // older tombstone

        let event = try #require(try event(stack.context))
        #expect(event.title == "edited") // not deleted by the stale tombstone
    }

    @Test("a tombstone for an unknown row is a no-op")
    func tombstoneForUnknownRowIsNoOp() throws {
        let stack = try makeStack()
        try stack.applier.apply(eventChange(id: UUID(), title: "x", updatedAt: t1, deletedAt: t1))

        #expect(try stack.context.fetch(FetchDescriptor<EventModel>()).isEmpty)
    }

    @Test("a delete and an edit converge to the newer one regardless of order")
    func deleteEditConvergesByLWW() throws {
        let id = UUID()
        let setup = [try eventChange(id: id, title: "init", updatedAt: t0)]
        // A delete at t1 and an edit at t2 — the later (edit) wins, on both orders.
        let concurrent = [
            try eventChange(id: id, title: "x", updatedAt: t1, deletedAt: t1),
            try eventChange(id: id, title: "resurrected", updatedAt: t2),
        ]

        let forward = try device(setup: setup, concurrent: concurrent)
        let reversed = try device(setup: setup, concurrent: Array(concurrent.reversed()))

        #expect(forward.eventTitles[id] == "resurrected") // newer edit beats older delete
        #expect(forward == reversed)
    }
}
