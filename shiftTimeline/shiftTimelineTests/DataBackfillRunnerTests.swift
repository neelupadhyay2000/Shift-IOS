import Foundation
import Models
import Services
@testable import shiftTimeline
import SwiftData
import Testing

/// `DataBackfillRunner` gates the one-time backfill so it
/// enqueues the local graph at most once per account per device, and proves the
/// two-device case converges via id dedupe rather than a shared flag.
@Suite("Backfill runner (run-once gate)")
@MainActor
struct DataBackfillRunnerTests {

    /// Stable ids so two simulated devices seed the *same* CloudKit-era rows.
    private struct GraphIDs {
        let event = UUID()
        let track = UUID()
        let block = UUID()
    }

    /// Holds the `ModelContainer` alive for the test's duration — a bare
    /// `container.mainContext` whose container is released traps in SwiftData on
    /// the next `insert`. `context` always returns the container's main context.
    private struct Device {
        let container: ModelContainer
        @MainActor var context: ModelContext { container.mainContext }
    }

    private func makeDevice() throws -> Device {
        let container = try PersistenceController.forTesting()
        container.mainContext.autosaveEnabled = false
        return Device(container: container)
    }

    private func makeStore() throws -> BackfillCompletionStore {
        BackfillCompletionStore(
            defaults: try #require(
                UserDefaults(suiteName: "DataBackfillRunnerTests.\(UUID().uuidString)")
            )
        )
    }

    /// Seeds an event → track → block graph through the *local* provider (no
    /// enqueue) so the outbox is empty until the runner fires.
    private func seed(_ context: ModelContext, ids: GraphIDs = GraphIDs()) async throws {
        let local = SwiftDataRepositoryProvider(context: context)
        let event = EventModel(id: ids.event, title: "Gala", date: fixedTimestamp, latitude: 1, longitude: 2)
        let track = TimelineTrack(id: ids.track, name: "Main", sortOrder: 0)
        let block = TimeBlockModel(id: ids.block, title: "Ceremony", scheduledStart: fixedTimestamp, duration: 1800)
        try await local.events.insert(event)
        try await local.tracks.insert(track, into: event)
        try await local.blocks.insert(block, into: track)
        try context.save()
    }

    private func outbox(_ context: ModelContext) throws -> [OutboxEntry] {
        try context.fetch(FetchDescriptor<OutboxEntry>(sortBy: [SortDescriptor(\.sequence)]))
    }

    // MARK: - Run-once gate

    @Test("first run enqueues the graph and marks the account complete")
    func firstRunEnqueuesAndMarks() async throws {
        let device = try makeDevice()
        try await seed(device.context)
        let store = try makeStore()
        let profile = UUID()

        await DataBackfillRunner(context: device.context, store: store).runIfNeeded(profileID: profile)

        #expect(try outbox(device.context).isEmpty == false)
        #expect(store.hasCompleted(for: profile))
    }

    @Test("a second run for the same account is gated — no new entries")
    func secondRunIsGated() async throws {
        let device = try makeDevice()
        try await seed(device.context)
        let store = try makeStore()
        let profile = UUID()
        let runner = DataBackfillRunner(context: device.context, store: store)

        await runner.runIfNeeded(profileID: profile)
        let afterFirst = try outbox(device.context).count
        #expect(afterFirst > 0)

        await runner.runIfNeeded(profileID: profile)
        #expect(try outbox(device.context).count == afterFirst) // gated: nothing re-enqueued
    }

    @Test("the gate is per-account: another account isn't blocked by a completed one")
    func gateIsPerAccount() async throws {
        let device = try makeDevice()
        try await seed(device.context)
        let store = try makeStore()
        let accountA = UUID()
        let accountB = UUID()
        let runner = DataBackfillRunner(context: device.context, store: store)

        await runner.runIfNeeded(profileID: accountA)
        #expect(store.hasCompleted(for: accountA))
        #expect(store.hasCompleted(for: accountB) == false)

        // B has its own (incomplete) flag, so the runner proceeds for B and marks it.
        await runner.runIfNeeded(profileID: accountB)
        #expect(store.hasCompleted(for: accountB))
    }

    // MARK: - Two-device dedupe by id

    @Test("two devices on the same account enqueue identical id-keyed rows (upsert dedupes)")
    func twoDeviceDedupeByID() async throws {
        let ids = GraphIDs()
        let profile = UUID()

        // Device 1 — its own store/defaults and model container.
        let device1 = try makeDevice()
        try await seed(device1.context, ids: ids)
        await DataBackfillRunner(context: device1.context, store: try makeStore()).runIfNeeded(profileID: profile)
        let ids1 = Set(try outbox(device1.context).map(\.rowID))

        // Device 2 — same account, same CloudKit-mirrored ids, independent flag.
        let device2 = try makeDevice()
        try await seed(device2.context, ids: ids)
        await DataBackfillRunner(context: device2.context, store: try makeStore()).runIfNeeded(profileID: profile)
        let ids2 = Set(try outbox(device2.context).map(\.rowID))

        // Both devices target the identical row ids → the server upsert-by-id
        // collapses the two uploads into one row each (no duplicates).
        #expect(ids1 == ids2)
        #expect(ids1.contains(ids.event))
        #expect(ids1.contains(ids.track))
        #expect(ids1.contains(ids.block))
    }

    // MARK: - Empty store

    @Test("an account with no local data is still marked complete (won't re-check each launch)")
    func emptyStoreMarksComplete() async throws {
        let device = try makeDevice()
        let store = try makeStore()
        let profile = UUID()

        await DataBackfillRunner(context: device.context, store: store).runIfNeeded(profileID: profile)

        #expect(try outbox(device.context).isEmpty)
        #expect(store.hasCompleted(for: profile))
    }
}
