import Foundation
@testable import shiftTimeline
import Testing

/// SHIFT-657: the backfill must run exactly once per account, gated by a local
/// completion flag keyed by profile id (not a single global boolean). Two
/// devices on the same account each run once; the duplicate uploads collapse
/// server-side via the id-keyed upsert, so the flag is intentionally per-device.
@Suite("Backfill completion flag")
struct BackfillCompletionStoreTests {

    private func makeStore() throws -> BackfillCompletionStore {
        BackfillCompletionStore(
            defaults: try #require(
                UserDefaults(suiteName: "BackfillCompletionStoreTests.\(UUID().uuidString)")
            )
        )
    }

    @Test("an account starts uncompleted")
    func startsUncompleted() throws {
        let store = try makeStore()
        #expect(store.hasCompleted(for: UUID()) == false)
    }

    @Test("marking completes only that account, not every account")
    func marksPerAccount() throws {
        let store = try makeStore()
        let a = UUID()
        let b = UUID()
        store.markCompleted(for: a)
        #expect(store.hasCompleted(for: a))
        #expect(store.hasCompleted(for: b) == false) // per-account, not a global flag
    }

    @Test("marking the same account twice is idempotent")
    func markIdempotent() throws {
        let store = try makeStore()
        let a = UUID()
        store.markCompleted(for: a)
        store.markCompleted(for: a)
        #expect(store.hasCompleted(for: a))
    }

    @Test("completion persists across store instances on the same defaults")
    func persistsAcrossInstances() throws {
        let defaults = try #require(
            UserDefaults(suiteName: "BackfillCompletionStoreTests.\(UUID().uuidString)")
        )
        let account = UUID()
        BackfillCompletionStore(defaults: defaults).markCompleted(for: account)
        // A fresh store (e.g. on the next launch) sees the persisted flag.
        #expect(BackfillCompletionStore(defaults: defaults).hasCompleted(for: account))
    }
}
