import Foundation
import Models
import Services
@testable import shiftTimeline
import SwiftData
import Supabase
import Testing

/// SHIFT-615: timeline conflict resolution. Timeline rows are planner-authoritative
/// (only the owner can write them — enforced server-side by RLS); between the
/// owner's own devices, the apply layer resolves last-write-wins by server
/// `updated_at`, so a stale remote change never clobbers a newer local version
/// regardless of arrival order. (Multi-device convergence scenarios: SHIFT-617.)
@Suite("Conflict resolution — timeline LWW")
@MainActor
struct ConflictResolutionTests {

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

    private func eventChange(id: UUID, title: String, updatedAt: Date?) throws -> RealtimeChange {
        let dto = EventDTO(
            id: id, ownerID: UUID(), title: title, date: PostgresTimestamp(t1),
            status: "planning", updatedAt: PostgresTimestamp(updatedAt)
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
}
