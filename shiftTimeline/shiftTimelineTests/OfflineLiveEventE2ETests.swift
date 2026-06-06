import Foundation
import Models
import Services
@testable import shiftTimeline
import SwiftData
import Supabase
import Testing

/// SHIFT-619 — the offline epic's exit gate. Two devices build and run a live
/// event **offline** (writes queued in each device's Outbox), then reconnect and
/// flush + pull through a shared in-memory server. Proves the whole offline
/// stack — enqueue (608) → flush (611) → delta (614) → apply + LWW (615/616) →
/// soft-delete/tombstone (618) — converges both devices to one state.
@Suite("Offline live-event E2E")
@MainActor
struct OfflineLiveEventE2ETests {

    /// An in-memory stand-in for Supabase: a key-value table store that stamps a
    /// monotonic server `updated_at` on every write (so LWW resolves by flush
    /// order, exactly like Postgres' trigger) and serves deltas by
    /// `updated_at > since`. Soft-deletes set `deleted_at` and bump `updated_at`.
    actor FakeServer {
        private var tables: [String: [String: JSONObject]] = [:]
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
        }

        func softDelete(table: String, key: String) {
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
    }

    /// Routes an Outbox item to the ``FakeServer`` (upsert by id, soft-delete by id).
    @MainActor
    struct FakeServerSender: OutboxSending {
        let server: FakeServer
        func send(_ item: OutboxItem) async throws {
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

    // MARK: - Device

    @MainActor
    struct Device {
        let container: ModelContainer
        let context: ModelContext
        let provider: OutboxRepositoryProvider
        let flusher: OutboxFlusher
        let reconciler: DeltaReconciler
    }

    private func makeDevice(server: FakeServer, ownerID: UUID) throws -> Device {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        context.autosaveEnabled = false
        let provider = OutboxRepositoryProvider(
            context: context,
            local: SwiftDataRepositoryProvider(context: context),
            currentOwnerID: { ownerID }
        )
        let flusher = OutboxFlusher(context: context, remote: FakeServerSender(server: server))
        let watermarks = LastPulledStore(defaults: try #require(UserDefaults(suiteName: "E2E.\(UUID().uuidString)")))
        let reconciler = DeltaReconciler(
            source: FakeServerDeltaSource(server: server),
            applier: RealtimeChangeApplier(context: context),
            watermarks: watermarks
        )
        return Device(container: container, context: context, provider: provider, flusher: flusher, reconciler: reconciler)
    }

    /// The comparable converged state of a device.
    private struct State: Equatable {
        let eventTitles: [UUID: String]
        let blockTitles: [UUID: String]
        let shiftCount: Int
    }

    private func state(_ context: ModelContext) throws -> State {
        State(
            eventTitles: Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<EventModel>()).map { ($0.id, $0.title) }),
            blockTitles: Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<TimeBlockModel>()).map { ($0.id, $0.title) }),
            shiftCount: try context.fetch(FetchDescriptor<ShiftRecord>()).count
        )
    }

    // MARK: - E2E

    @Test("two devices build/run a live event offline and converge on reconnect")
    func offlineLiveEventConvergesOnReconnect() async throws {
        let server = FakeServer()
        let ownerID = UUID()
        let deviceA = try makeDevice(server: server, ownerID: ownerID)
        let deviceB = try makeDevice(server: server, ownerID: ownerID)
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        // 1. Device A builds the event online and flushes it to the server.
        let event = EventModel(title: "Wedding", date: start, latitude: 0, longitude: 0)
        let track = TimelineTrack(name: "Main", sortOrder: 0)
        let block1 = TimeBlockModel(title: "Ceremony", scheduledStart: start, duration: 1800)
        let block2 = TimeBlockModel(title: "Cocktails", scheduledStart: start, duration: 3600)
        try await deviceA.provider.events.insert(event)
        try await deviceA.provider.tracks.insert(track, into: event)
        try await deviceA.provider.blocks.insert(block1, into: track)
        try await deviceA.provider.blocks.insert(block2, into: track)
        try deviceA.context.save()
        await deviceA.flusher.flush()

        // 2. Device B hydrates from the server.
        try await deviceB.reconciler.reconcile()
        #expect(try state(deviceA.context) == state(deviceB.context)) // same starting point

        // 3. Both go offline and edit. A: rename event + block1, delete block2.
        event.title = "A-Wedding"
        block1.title = "A-Ceremony"
        try await deviceA.provider.blocks.delete(block2)
        try await deviceA.provider.events.save()

        // B: rename the event (conflict) and run a shift.
        let bEvent = try #require(try deviceB.context.fetch(FetchDescriptor<EventModel>()).first)
        bEvent.title = "B-Wedding"
        PersistenceController.recordShift(deltaMinutes: 10, triggeredBy: .manual, event: bEvent, into: deviceB.context)
        try await deviceB.provider.events.save()

        // 4. Reconnect: A flushes first, then B — so B's event edit lands later.
        await deviceA.flusher.flush()
        await deviceB.flusher.flush()

        // 5. Both pull the delta.
        try await deviceA.reconciler.reconcile()
        try await deviceB.reconciler.reconcile()

        // 6. Converged, and correct per the conflict policy.
        let finalA = try state(deviceA.context)
        let finalB = try state(deviceB.context)
        #expect(finalA == finalB)                              // the exit gate: identical state
        #expect(finalA.eventTitles[event.id] == "B-Wedding")  // B flushed last → wins the conflict
        #expect(finalA.blockTitles[block1.id] == "A-Ceremony") // only A edited block1
        #expect(finalA.blockTitles[block2.id] == nil)          // A's delete propagated as a tombstone
        #expect(finalA.shiftCount == 1)                        // B's shift propagated
    }
}
