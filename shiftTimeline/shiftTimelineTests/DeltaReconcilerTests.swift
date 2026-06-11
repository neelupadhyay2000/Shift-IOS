import Foundation
import Models
import Services
@testable import shiftTimeline
import SwiftData
import Testing

/// On foreground, rows changed since the watermark are pulled and
/// merged into SwiftData (reusing the realtime applier), and the watermark
/// advances. The Supabase delta source hits the network (online acceptance);
/// the merge + watermark logic is driven here against a canned delta.
@Suite("Delta reconciler")
@MainActor
struct DeltaReconcilerTests {

    /// Returns a canned delta and records the watermark it was asked for.
    actor FakeDeltaSource: DeltaSource {
        private let snapshot: HydrationSnapshot
        private(set) var receivedSince: Date?
        init(_ snapshot: HydrationSnapshot) { self.snapshot = snapshot }
        func fetchDelta(since: Date?) async throws -> HydrationSnapshot {
            receivedSince = since
            return snapshot
        }
    }

    private let t1 = Date(timeIntervalSince1970: 1_780_000_000)
    private let t2 = Date(timeIntervalSince1970: 1_790_000_000)

    private func makeWatermarks() throws -> LastPulledStore {
        LastPulledStore(defaults: try #require(UserDefaults(suiteName: "DeltaReconcilerTests.\(UUID().uuidString)")))
    }

    private func eventDTO(_ id: UUID, title: String, updatedAt: Date, deletedAt: Date? = nil) -> EventDTO {
        EventDTO(
            id: id, ownerID: UUID(), title: title, date: PostgresTimestamp(t1),
            status: "planning", updatedAt: PostgresTimestamp(updatedAt), deletedAt: PostgresTimestamp(deletedAt)
        )
    }

    // MARK: - Merge

    @Test("a delta inserts rows missed while backgrounded and advances the watermark")
    func deltaInsertsAndAdvancesWatermark() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let watermarks = try makeWatermarks()
        let id = UUID()
        let source = FakeDeltaSource(HydrationSnapshot(events: [eventDTO(id, title: "Gala", updatedAt: t1)]))
        let reconciler = DeltaReconciler(
            source: source, applier: RealtimeChangeApplier(context: context), watermarks: watermarks
        )

        try await reconciler.reconcile()

        let events = try context.fetch(FetchDescriptor<EventModel>())
        #expect(events.map(\.id) == [id])
        #expect(events.first?.title == "Gala")
        #expect(watermarks.lastPulled(for: .account) == t1)
        #expect(await source.receivedSince == nil) // first pull: no watermark yet
    }

    @Test("a delta updates an existing row in place (no duplicate)")
    func deltaUpdatesInPlace() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let id = UUID()
        context.insert(EventModel(id: id, title: "Old", date: fixedTimestamp, latitude: 0, longitude: 0))
        try context.save()

        let source = FakeDeltaSource(HydrationSnapshot(events: [eventDTO(id, title: "New", updatedAt: t2)]))
        let reconciler = DeltaReconciler(
            source: source, applier: RealtimeChangeApplier(context: context), watermarks: try makeWatermarks()
        )

        try await reconciler.reconcile()

        let events = try context.fetch(FetchDescriptor<EventModel>())
        #expect(events.count == 1)
        #expect(events.first?.title == "New")
    }

    @Test("a tombstone in the delta deletes the local row")
    func deltaTombstoneDeletesLocalRow() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let watermarks = try makeWatermarks()
        let id = UUID()
        context.insert(EventModel(id: id, title: "Doomed", date: fixedTimestamp, latitude: 0, longitude: 0))
        try context.save()

        let source = FakeDeltaSource(HydrationSnapshot(
            events: [eventDTO(id, title: "Doomed", updatedAt: t2, deletedAt: t2)]
        ))
        let reconciler = DeltaReconciler(
            source: source, applier: RealtimeChangeApplier(context: context), watermarks: watermarks
        )

        try await reconciler.reconcile()

        #expect(try context.fetch(FetchDescriptor<EventModel>()).isEmpty)
        #expect(watermarks.lastPulled(for: .account) == t2)
    }

    @Test("a delta wires relationships (track to its event)")
    func deltaWiresRelationships() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let eventID = UUID(), trackID = UUID()
        let source = FakeDeltaSource(HydrationSnapshot(
            events: [eventDTO(eventID, title: "E", updatedAt: t1)],
            tracks: [TrackDTO(id: trackID, eventID: eventID, name: "Main", sortOrder: 0, isDefault: false, updatedAt: PostgresTimestamp(t1))]
        ))
        let reconciler = DeltaReconciler(
            source: source, applier: RealtimeChangeApplier(context: context), watermarks: try makeWatermarks()
        )

        try await reconciler.reconcile()

        let event = try #require(try context.fetch(FetchDescriptor<EventModel>()).first)
        #expect(event.tracks?.map(\.id) == [trackID])
    }

    // MARK: - Watermark

    @Test("the delta is fetched from the persisted watermark; an empty delta leaves it")
    func deltaUsesPersistedWatermarkAndEmptyLeavesIt() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let watermarks = try makeWatermarks()
        watermarks.recordPull(at: t1, for: .account)

        let source = FakeDeltaSource(HydrationSnapshot()) // empty delta
        let reconciler = DeltaReconciler(
            source: source, applier: RealtimeChangeApplier(context: context), watermarks: watermarks
        )

        try await reconciler.reconcile()

        #expect(await source.receivedSince == t1)
        #expect(watermarks.lastPulled(for: .account) == t1) // unchanged
    }

    @Test("the watermark advances to the newest timestamp in the delta")
    func watermarkAdvancesToMax() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let watermarks = try makeWatermarks()
        let source = FakeDeltaSource(HydrationSnapshot(events: [
            eventDTO(UUID(), title: "A", updatedAt: t1),
            eventDTO(UUID(), title: "B", updatedAt: t2),
        ]))
        let reconciler = DeltaReconciler(
            source: source, applier: RealtimeChangeApplier(context: context), watermarks: watermarks
        )

        try await reconciler.reconcile()

        #expect(watermarks.lastPulled(for: .account) == t2)
    }

    @Test("highWaterMark is the max across main and junction tables")
    func highWaterMarkIsMaxAcrossTables() {
        let snapshot = HydrationSnapshot(
            events: [eventDTO(UUID(), title: "A", updatedAt: t1)],
            blockVendors: [BlockVendorDTO(
                blockID: UUID(), eventVendorID: UUID(), eventID: UUID(), createdAt: PostgresTimestamp(t2)
            )]
        )
        #expect(DeltaReconciler.highWaterMark(snapshot) == t2)
        #expect(DeltaReconciler.highWaterMark(HydrationSnapshot()) == nil)
    }
}
