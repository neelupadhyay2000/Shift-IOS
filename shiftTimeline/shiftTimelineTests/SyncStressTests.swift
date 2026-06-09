import Foundation
import Models
import Services
@testable import shiftTimeline
import SwiftData
import Supabase
import Testing

/// SHIFT-662 — the hardening epic's stress gate. Drives the offline sync stack
/// (enqueue → flush → delta → apply/LWW → tombstone) under the three loads E16
/// calls out: a **reconnect storm** (a flurry of flush triggers), a
/// **large timeline** (200+ blocks), and **concurrent events** (many events
/// syncing at once). Each proves the acceptance criteria: **no data loss, no
/// duplication, and convergence** across two devices.
///
/// Like ``OfflineLiveEventE2ETests`` it runs against an in-memory stand-in for
/// Supabase, but the server here also **logs every send** so a re-send (the
/// signature of a duplication bug) is detectable — the keyed row store alone
/// can't catch one because it dedupes by id by construction.
@Suite("Sync stress — reconnect storm · large timeline · concurrent events")
@MainActor
struct SyncStressTests {

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - In-memory server

    /// Key-value table store stamping a monotonic server `updated_at` on every
    /// write (so LWW resolves by flush order, like Postgres' trigger) and serving
    /// deltas by `updated_at > since`. Soft-deletes set `deleted_at` + bump
    /// `updated_at`. It also keeps a per-row **send tally** so a test can assert
    /// each logical row was delivered exactly once — the real no-duplication guard
    /// (the keyed store dedupes by id, so it can't surface a re-send on its own).
    actor FakeServer {
        private var tables: [String: [String: JSONObject]] = [:]
        private var sendTally: [String: Int] = [:]
        private var tick = 0
        private let base = Date(timeIntervalSince1970: 1_800_000_000)

        private func stamp() -> AnyJSON {
            tick += 1
            return .string(SupabaseTimestamp.string(from: base.addingTimeInterval(Double(tick))))
        }

        func upsert(table: String, key: String, record: JSONObject) {
            var row = record
            row["updated_at"] = stamp()
            tables[table, default: [:]][key] = row
            sendTally["\(table):\(key)", default: 0] += 1
        }

        func softDelete(table: String, key: String) {
            sendTally["\(table):\(key)", default: 0] += 1
            guard var row = tables[table]?[key] else { return }
            let now = stamp()
            row["updated_at"] = now
            row["deleted_at"] = now
            tables[table]?[key] = row
        }

        func rows(table: String, since: Date?) -> [JSONObject] {
            let all = Array((tables[table] ?? [:]).values)
            guard let since else { return all }
            return all.filter { row in
                guard let raw = row["updated_at"]?.stringValue,
                      let updated = SupabaseTimestamp.date(from: raw) else { return false }
                return updated > since
            }
        }

        func count(table: String) -> Int { tables[table]?.count ?? 0 }

        /// The most times any single logical row was written — `1` means every
        /// row reached the server exactly once (no re-send / duplication).
        func maxSendsPerRow() -> Int { sendTally.values.max() ?? 0 }
    }

    /// Routes an Outbox item to the ``FakeServer`` (idempotent upsert / soft-delete
    /// by id). Can be told to fail the first N sends — modelling a flaky reconnect
    /// — to prove the flusher converges without re-sending an already-delivered row.
    @MainActor
    final class FakeServerSender: OutboxSending {
        let server: FakeServer
        var failuresRemaining: Int

        init(server: FakeServer, failuresRemaining: Int = 0) {
            self.server = server
            self.failuresRemaining = failuresRemaining
        }

        enum Failure: Error { case transientNetwork }

        func send(_ item: OutboxItem) async throws {
            if failuresRemaining > 0 {
                failuresRemaining -= 1
                throw Failure.transientNetwork
            }
            switch item.operation {
            case .insert, .update:
                guard let payload = item.payload else { return }
                let record = try JSONDecoder().decode(JSONObject.self, from: payload)
                await server.upsert(table: item.table, key: item.rowID.uuidString, record: record)
            case .delete:
                await server.softDelete(table: item.table, key: item.rowID.uuidString)
            }
        }
    }

    /// Serves deltas from the ``FakeServer``.
    struct FakeServerDeltaSource: DeltaSource {
        let server: FakeServer
        func fetchDelta(since: Date?) async throws -> HydrationSnapshot {
            HydrationSnapshot(
                events: try await decode("events", since),
                tracks: try await decode("tracks", since),
                blocks: try await decode("blocks", since),
                vendors: try await decode("event_vendors", since),
                shiftRecords: try await decode("shift_records", since)
            )
        }

        private func decode<Row: Decodable>(_ table: String, _ since: Date?) async throws -> [Row] {
            try await server.rows(table: table, since: since)
                .map { try $0.decode(as: Row.self, decoder: JSONDecoder()) }
        }
    }

    // MARK: - Device harness

    @MainActor
    struct Device {
        let container: ModelContainer
        let context: ModelContext
        let provider: OutboxRepositoryProvider
        let sender: FakeServerSender
        let flusher: OutboxFlusher
        let reconciler: DeltaReconciler
    }

    private func makeDevice(
        server: FakeServer,
        ownerID: UUID,
        senderFailures: Int = 0
    ) throws -> Device {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        context.autosaveEnabled = false
        let provider = OutboxRepositoryProvider(
            context: context,
            local: SwiftDataRepositoryProvider(context: context),
            currentOwnerID: { ownerID }
        )
        let sender = FakeServerSender(server: server, failuresRemaining: senderFailures)
        // No-op sleep so backoff retries are instant and deterministic under load.
        let flusher = OutboxFlusher(context: context, remote: sender, sleep: { _ in })
        let watermarks = LastPulledStore(
            defaults: try #require(UserDefaults(suiteName: "Stress.\(UUID().uuidString)"))
        )
        let reconciler = DeltaReconciler(
            source: FakeServerDeltaSource(server: server),
            applier: RealtimeChangeApplier(context: context),
            watermarks: watermarks
        )
        return Device(
            container: container, context: context, provider: provider,
            sender: sender, flusher: flusher, reconciler: reconciler
        )
    }

    /// The comparable converged state of a device.
    private struct State: Equatable {
        let eventTitles: [UUID: String]
        let trackCount: Int
        let blockTitles: [UUID: String]
    }

    private func state(_ context: ModelContext) throws -> State {
        State(
            eventTitles: Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<EventModel>()).map { ($0.id, $0.title) }),
            trackCount: try context.fetch(FetchDescriptor<TimelineTrack>()).count,
            blockTitles: Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<TimeBlockModel>()).map { ($0.id, $0.title) })
        )
    }

    private func outboxCount(_ context: ModelContext) throws -> Int {
        try context.fetch(FetchDescriptor<OutboxEntry>()).count
    }

    /// Builds an event with `blockCount` blocks on one track, offline (writes land
    /// in the Outbox). Returns the event and its block ids in insertion order.
    @discardableResult
    private func buildEvent(
        on device: Device, title: String, blockCount: Int
    ) async throws -> (event: EventModel, blockIDs: [UUID]) {
        let event = EventModel(title: title, date: start, latitude: 0, longitude: 0)
        let track = TimelineTrack(name: "Main", sortOrder: 0)
        try await device.provider.events.insert(event)
        try await device.provider.tracks.insert(track, into: event)
        var blockIDs: [UUID] = []
        for index in 0..<blockCount {
            let block = TimeBlockModel(
                title: "\(title)-Block-\(index)",
                scheduledStart: start.addingTimeInterval(Double(index) * 600),
                duration: 600
            )
            try await device.provider.blocks.insert(block, into: track)
            blockIDs.append(block.id)
        }
        try device.context.save()
        return (event, blockIDs)
    }

    // MARK: - 1. Reconnect storm

    @Test("a storm of overlapping flush triggers drains the queue exactly once (no re-sends)")
    func reconnectStormDrainsExactlyOnce() async throws {
        let server = FakeServer()
        let ownerID = UUID()
        let device = try makeDevice(server: server, ownerID: ownerID)
        let (_, blockIDs) = try await buildEvent(on: device, title: "Storm", blockCount: 60)
        let enqueued = try outboxCount(device.context) // event + track + 60 blocks

        // Walk in and out of signal: 50 reconnects fire flush concurrently. The
        // flusher's single-flight guard must collapse them — the real send happens
        // once and the rest are no-ops, even though each suspends at `await send`.
        var storm: [Task<Void, Never>] = []
        for _ in 0..<50 { storm.append(Task { @MainActor in await device.flusher.flush() }) }
        for trigger in storm { await trigger.value }

        #expect(enqueued == 62)
        #expect(blockIDs.count == 60)
        #expect(try outboxCount(device.context) == 0)          // fully drained
        #expect(await server.count(table: "events") == 1)
        #expect(await server.count(table: "blocks") == 60)     // no rows lost
        #expect(await server.maxSendsPerRow() == 1)            // and none re-sent
    }

    @Test("a flapping connection (sender fails then recovers) still converges once, no duplication")
    func flappingConnectionConvergesWithoutDuplication() async throws {
        let server = FakeServer()
        let ownerID = UUID()
        // The first 5 sends fail (signal drops mid-flush); the backoff retry path
        // re-drives the head — but an already-delivered row must never be re-sent.
        let device = try makeDevice(server: server, ownerID: ownerID, senderFailures: 5)
        try await buildEvent(on: device, title: "Flap", blockCount: 40)

        // Drive deterministic FIFO passes (the primitive each reconnect retry runs)
        // until the queue drains. The head fails its first five attempts — each a
        // dropped send that never reaches the server — then recovers, after which
        // the whole queue empties. A bounded loop guards against non-convergence.
        var passes = 0
        while await device.flusher.flushOnce() != .drained {
            passes += 1
            #expect(passes < 50)
        }

        #expect(passes == 5)                                  // five flaps before recovery
        #expect(try outboxCount(device.context) == 0)
        #expect(await server.count(table: "events") == 1)
        #expect(await server.count(table: "blocks") == 40)
        #expect(await server.maxSendsPerRow() == 1) // failures didn't double-deliver
    }

    @Test("a burst of debounced reconnect triggers coalesces into a single flush")
    func debouncedReconnectBurstCoalesces() async throws {
        let server = FakeServer()
        let device = try makeDevice(server: server, ownerID: UUID())
        try await buildEvent(on: device, title: "Debounce", blockCount: 30)

        var flushCount = 0
        let scheduler = FlushScheduler(interval: 0, sleep: { _ in }) {
            flushCount += 1
            await device.flusher.flush()
        }

        // 100 connectivity flaps in one window — each cancels the prior pending
        // flush, so only the last survives.
        for _ in 0..<100 { scheduler.requestFlush() }
        await scheduler.pendingTask?.value

        #expect(flushCount == 1)                            // storm tamed to one flush
        #expect(try outboxCount(device.context) == 0)
        #expect(await server.count(table: "blocks") == 30)
        #expect(await server.maxSendsPerRow() == 1)
    }

    // MARK: - 2. Large timeline (200+ blocks)

    @Test("a 250-block timeline syncs and hydrates a second device with no loss or duplication")
    func largeTimelineConvergesAcrossDevices() async throws {
        let server = FakeServer()
        let ownerID = UUID()
        let deviceA = try makeDevice(server: server, ownerID: ownerID)
        let deviceB = try makeDevice(server: server, ownerID: ownerID)

        let (event, blockIDs) = try await buildEvent(on: deviceA, title: "Festival", blockCount: 250)
        await deviceA.flusher.flush()

        // The whole graph reached the server intact.
        #expect(await server.count(table: "blocks") == 250)
        #expect(await server.maxSendsPerRow() == 1)
        #expect(try outboxCount(deviceA.context) == 0)

        // A clean second device reconstructs the entire timeline from the server.
        try await deviceB.reconciler.reconcile()

        let blocksOnB = try deviceB.context.fetch(FetchDescriptor<TimeBlockModel>())
        #expect(blocksOnB.count == 250)                                   // none lost
        #expect(Set(blocksOnB.map(\.id)).count == 250)                    // none duplicated
        #expect(Set(blocksOnB.map(\.id)) == Set(blockIDs))               // exactly the right ids
        #expect(try state(deviceA.context) == state(deviceB.context))    // converged
        #expect(try deviceB.context.fetch(FetchDescriptor<EventModel>()).first?.id == event.id)
    }

    @Test("concurrent edits across a large timeline on two devices converge by LWW")
    func largeTimelineConcurrentEditsConverge() async throws {
        let server = FakeServer()
        let ownerID = UUID()
        let deviceA = try makeDevice(server: server, ownerID: ownerID)
        let deviceB = try makeDevice(server: server, ownerID: ownerID)

        // A builds 200 blocks and both devices sync to the same baseline.
        let (_, blockIDs) = try await buildEvent(on: deviceA, title: "Gala", blockCount: 200)
        await deviceA.flusher.flush()
        try await deviceB.reconciler.reconcile()
        #expect(try state(deviceA.context) == state(deviceB.context))

        // Both devices edit a disjoint half of the timeline offline.
        let blocksA = try deviceA.context.fetch(FetchDescriptor<TimeBlockModel>())
        for block in blocksA where blockIDs.prefix(100).contains(block.id) {
            block.title = "A-edit-\(block.id.uuidString.prefix(4))"
        }
        try await deviceA.provider.blocks.save()

        let blocksB = try deviceB.context.fetch(FetchDescriptor<TimeBlockModel>())
        for block in blocksB where blockIDs.suffix(100).contains(block.id) {
            block.title = "B-edit-\(block.id.uuidString.prefix(4))"
        }
        try await deviceB.provider.blocks.save()

        // Reconnect both, then cross-pull.
        await deviceA.flusher.flush()
        await deviceB.flusher.flush()
        try await deviceA.reconciler.reconcile()
        try await deviceB.reconciler.reconcile()

        let finalA = try state(deviceA.context)
        let finalB = try state(deviceB.context)
        #expect(finalA == finalB)                       // converged
        #expect(finalA.blockTitles.count == 200)        // no loss, no duplication
        // Every row was written at most twice — its initial insert plus one edit.
        // A third send would betray a re-send/duplication bug under load.
        #expect(await server.maxSendsPerRow() == 2)
    }

    // MARK: - 3. Concurrent events

    @Test("twelve events built concurrently all sync and hydrate intact")
    func concurrentEventsConvergeAcrossDevices() async throws {
        let server = FakeServer()
        let ownerID = UUID()
        let deviceA = try makeDevice(server: server, ownerID: ownerID)
        let deviceB = try makeDevice(server: server, ownerID: ownerID)

        let eventCount = 12
        let blocksPerEvent = 8
        var allEventIDs: Set<UUID> = []
        for index in 0..<eventCount {
            let (event, _) = try await buildEvent(on: deviceA, title: "Event-\(index)", blockCount: blocksPerEvent)
            allEventIDs.insert(event.id)
        }
        await deviceA.flusher.flush()

        #expect(await server.count(table: "events") == eventCount)
        #expect(await server.count(table: "blocks") == eventCount * blocksPerEvent)
        #expect(await server.maxSendsPerRow() == 1)
        #expect(try outboxCount(deviceA.context) == 0)

        try await deviceB.reconciler.reconcile()

        let eventsOnB = try deviceB.context.fetch(FetchDescriptor<EventModel>())
        #expect(eventsOnB.count == eventCount)
        #expect(Set(eventsOnB.map(\.id)) == allEventIDs)                                  // all events, no dup
        #expect(try deviceB.context.fetch(FetchDescriptor<TimeBlockModel>()).count == eventCount * blocksPerEvent)
        #expect(try state(deviceA.context) == state(deviceB.context))                     // converged
    }

    @Test("concurrent edits to different events on two devices don't cross-contaminate")
    func concurrentEventEditsStayIsolatedAndConverge() async throws {
        let server = FakeServer()
        let ownerID = UUID()
        let deviceA = try makeDevice(server: server, ownerID: ownerID)
        let deviceB = try makeDevice(server: server, ownerID: ownerID)

        // Shared baseline of 6 events.
        var events: [EventModel] = []
        for index in 0..<6 {
            let (event, _) = try await buildEvent(on: deviceA, title: "E\(index)", blockCount: 4)
            events.append(event)
        }
        await deviceA.flusher.flush()
        try await deviceB.reconciler.reconcile()
        #expect(try state(deviceA.context) == state(deviceB.context))

        // A renames the even-indexed events; B renames the odd-indexed ones —
        // disjoint, so every edit must survive (no cross-event clobber).
        let eventsA = try deviceA.context.fetch(FetchDescriptor<EventModel>())
        for event in eventsA where (events.firstIndex(where: { $0.id == event.id }) ?? 0) % 2 == 0 {
            event.title = "A-\(event.id.uuidString.prefix(4))"
        }
        try await deviceA.provider.events.save()

        let eventsB = try deviceB.context.fetch(FetchDescriptor<EventModel>())
        for event in eventsB where (events.firstIndex(where: { $0.id == event.id }) ?? 0) % 2 == 1 {
            event.title = "B-\(event.id.uuidString.prefix(4))"
        }
        try await deviceB.provider.events.save()

        await deviceA.flusher.flush()
        await deviceB.flusher.flush()
        try await deviceA.reconciler.reconcile()
        try await deviceB.reconciler.reconcile()

        let finalA = try state(deviceA.context)
        let finalB = try state(deviceB.context)
        #expect(finalA == finalB)                                   // converged
        #expect(finalA.eventTitles.count == 6)                      // all six survive
        #expect(finalA.eventTitles.values.filter { $0.hasPrefix("A-") }.count == 3)
        #expect(finalA.eventTitles.values.filter { $0.hasPrefix("B-") }.count == 3)
        // At most insert + one rename per row — no spurious re-sends.
        #expect(await server.maxSendsPerRow() == 2)
    }
}
