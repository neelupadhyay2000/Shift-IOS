import Foundation
@testable import shiftTimeline
import Testing

/// SHIFT-613: the `lastPulledAt` watermark is persisted per scope and advanced
/// after each pull.
@Suite("Last-pulled watermark store")
struct LastPulledStoreTests {

    private let t1 = Date(timeIntervalSince1970: 1_700_000_000)
    private let t2 = Date(timeIntervalSince1970: 1_800_000_000)

    /// A fresh, isolated `UserDefaults` so tests never touch real prefs.
    private func makeDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "LastPulledStoreTests.\(UUID().uuidString)"))
    }

    @Test("a scope with no recorded pull reads as nil")
    func unrecordedScopeIsNil() throws {
        let store = LastPulledStore(defaults: try makeDefaults())
        #expect(store.lastPulled(for: .account) == nil)
        #expect(store.lastPulled(for: .event(UUID())) == nil)
    }

    @Test("recording a pull persists the watermark for that scope")
    func recordingPersistsWatermark() throws {
        let store = LastPulledStore(defaults: try makeDefaults())
        store.recordPull(at: t1, for: .account)
        #expect(store.lastPulled(for: .account) == t1)
    }

    @Test("a later pull advances the watermark")
    func recordingAdvancesWatermark() throws {
        let store = LastPulledStore(defaults: try makeDefaults())
        store.recordPull(at: t1, for: .account)
        store.recordPull(at: t2, for: .account)
        #expect(store.lastPulled(for: .account) == t2)
    }

    @Test("scopes are independent")
    func scopesAreIndependent() throws {
        let store = LastPulledStore(defaults: try makeDefaults())
        let eventA = UUID()
        let eventB = UUID()

        store.recordPull(at: t1, for: .account)
        store.recordPull(at: t2, for: .event(eventA))

        #expect(store.lastPulled(for: .account) == t1)
        #expect(store.lastPulled(for: .event(eventA)) == t2)
        #expect(store.lastPulled(for: .event(eventB)) == nil)
    }

    @Test("the watermark survives across store instances (it is persisted)")
    func watermarkSurvivesNewInstance() throws {
        let defaults = try makeDefaults()
        let id = UUID()
        // Write with one instance…
        LastPulledStore(defaults: defaults).recordPull(at: t1, for: .event(id))
        // …read with a brand-new instance over the same defaults — proves the
        // value isn't in-memory state but actually persisted.
        let reopened = LastPulledStore(defaults: defaults)
        #expect(reopened.lastPulled(for: .event(id)) == t1)
    }

    @Test("reset clears a single scope")
    func resetClearsScope() throws {
        let store = LastPulledStore(defaults: try makeDefaults())
        store.recordPull(at: t1, for: .account)
        store.recordPull(at: t2, for: .event(UUID()))

        store.reset(.account)

        #expect(store.lastPulled(for: .account) == nil)
    }

    @Test("resetAll clears every watermark (e.g. on sign-out)")
    func resetAllClearsEverything() throws {
        let store = LastPulledStore(defaults: try makeDefaults())
        let event = UUID()
        store.recordPull(at: t1, for: .account)
        store.recordPull(at: t2, for: .event(event))

        store.resetAll()

        #expect(store.lastPulled(for: .account) == nil)
        #expect(store.lastPulled(for: .event(event)) == nil)
    }
}
