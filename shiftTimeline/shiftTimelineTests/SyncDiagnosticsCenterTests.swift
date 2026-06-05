import Foundation
import Testing
import Services

/// Tests for `SyncDiagnosticsCenter` — the single source of truth that feeds
/// both the in-app diagnostics screen and the TelemetryDeck bridge.
///
/// Each test injects a throwaway `UserDefaults` suite so it never touches the
/// real App Group store or the shared singleton.
@Suite struct SyncDiagnosticsCenterTests {

    /// Returns a center backed by an isolated, empty `UserDefaults` suite so
    /// tests can't interfere with each other or with the real App Group.
    private func makeCenter(maxEvents: Int = 500) -> (SyncDiagnosticsCenter, UserDefaults, String) {
        let suiteName = "test.syncDiagnostics.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Could not create test UserDefaults suite")
        }
        let key = "events"
        defaults.removeObject(forKey: key)
        let center = SyncDiagnosticsCenter(defaults: defaults, storageKey: key, maxEvents: maxEvents)
        return (center, defaults, key)
    }

    @Test func recordsNewestFirst() {
        let (center, _, _) = makeCenter()

        center.record(.subscribe, "started")
        center.record(.subscribe, "succeeded")

        #expect(center.events.count == 2)
        #expect(center.events.first?.name == "succeeded")
        #expect(center.events.last?.name == "started")
    }

    @Test func capsAtMaxEventsKeepingNewest() {
        let (center, _, _) = makeCenter(maxEvents: 3)

        for index in 1 ... 5 {
            center.record(.fetch, "tick-\(index)")
        }

        #expect(center.events.count == 3)
        // Newest-first: the last three ticks survive, tick-5 at the front.
        #expect(center.events.map(\.name) == ["tick-5", "tick-4", "tick-3"])
    }

    @Test func persistsAcrossInstancesViaInjectedDefaults() {
        let (center, defaults, key) = makeCenter()

        center.record(.applyRemote, "completed", params: ["events": "1", "blocks": "4"])

        // A fresh center reading the same defaults must reload the event.
        let reloaded = SyncDiagnosticsCenter(defaults: defaults, storageKey: key, maxEvents: 500)
        #expect(reloaded.events.count == 1)
        #expect(reloaded.events.first?.name == "completed")
        #expect(reloaded.events.first?.params["blocks"] == "4")
    }

    @Test func exportTextIncludesCategoryNameAndParams() {
        let (center, _, _) = makeCenter()

        center.record(.conflict, "skipped", params: ["reason": "notShared"], severity: .warning)

        let text = center.exportText()
        #expect(text.contains("conflict"))
        #expect(text.contains("skipped"))
        #expect(text.contains("reason"))
        #expect(text.contains("notShared"))
    }

    @Test func clearEmptiesMemoryAndStorage() {
        let (center, defaults, key) = makeCenter()

        center.record(.push, "received")
        center.clear()

        #expect(center.events.isEmpty)

        // Persisted store is also cleared — a fresh center loads nothing.
        let reloaded = SyncDiagnosticsCenter(defaults: defaults, storageKey: key, maxEvents: 500)
        #expect(reloaded.events.isEmpty)
    }

    @Test func recordIsThreadSafeUnderConcurrentWrites() async {
        let (center, _, _) = makeCenter(maxEvents: 10_000)

        await withTaskGroup(of: Void.self) { group in
            for index in 0 ..< 200 {
                group.addTask {
                    center.record(.fetch, "concurrent-\(index)")
                }
            }
        }

        // No crash, and every write landed.
        #expect(center.events.count == 200)
    }
}
