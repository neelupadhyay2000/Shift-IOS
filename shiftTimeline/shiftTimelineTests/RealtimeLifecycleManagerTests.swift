import Foundation
@testable import shiftTimeline
import Testing

@Suite("RealtimeLifecycleManager")
@MainActor
struct RealtimeLifecycleManagerTests {

    /// Records which events a channel was opened for; the returned stream never
    /// emits, so the consume `Task` stays alive until the manager cancels it.
    @MainActor
    final class FakeStreamSource {
        private(set) var openedEvents: [UUID] = []
        func open(_ eventID: UUID) -> AsyncStream<RealtimeChange> {
            openedEvents.append(eventID)
            return AsyncStream { _ in }
        }
    }

    private func makeManager(
        _ source: FakeStreamSource,
        isForeground: Bool = true
    ) -> RealtimeLifecycleManager {
        RealtimeLifecycleManager(openStream: source.open, consume: { _ in }, isForeground: isForeground)
    }

    @Test("subscribes when an event opens while foregrounded")
    func subscribesOnEventOpen() {
        let source = FakeStreamSource()
        let manager = makeManager(source)
        let id = UUID()

        manager.setActiveEvent(id)

        #expect(manager.isStreaming)
        #expect(manager.streamingEventID == id)
        #expect(source.openedEvents == [id])
    }

    @Test("does not subscribe while backgrounded")
    func noSubscriptionWhileBackgrounded() {
        let source = FakeStreamSource()
        let manager = makeManager(source, isForeground: false)

        manager.setActiveEvent(UUID())

        #expect(!manager.isStreaming)
        #expect(source.openedEvents.isEmpty)
    }

    @Test("tears the channel down on background")
    func tearsDownOnBackground() {
        let source = FakeStreamSource()
        let manager = makeManager(source)
        manager.setActiveEvent(UUID())
        #expect(manager.isStreaming)

        manager.didEnterBackground()

        #expect(!manager.isStreaming)
        #expect(manager.streamingEventID == nil)
    }

    @Test("resubscribes to the active event on foreground")
    func resubscribesOnForeground() {
        let source = FakeStreamSource()
        let manager = makeManager(source)
        let id = UUID()
        manager.setActiveEvent(id)
        manager.didEnterBackground()
        #expect(!manager.isStreaming)

        manager.didEnterForeground()

        #expect(manager.isStreaming)
        #expect(manager.streamingEventID == id)
        #expect(source.openedEvents == [id, id]) // opened on first open + on foreground
    }

    @Test("tears down when the event closes")
    func tearsDownOnEventClose() {
        let source = FakeStreamSource()
        let manager = makeManager(source)
        manager.setActiveEvent(UUID())
        #expect(manager.isStreaming)

        manager.setActiveEvent(nil)

        #expect(!manager.isStreaming)
        #expect(manager.streamingEventID == nil)
    }

    @Test("switching events tears down the old channel and opens the new")
    func switchingEventsResubscribes() {
        let source = FakeStreamSource()
        let manager = makeManager(source)
        let first = UUID(), second = UUID()

        manager.setActiveEvent(first)
        manager.setActiveEvent(second)

        #expect(manager.streamingEventID == second)
        #expect(source.openedEvents == [first, second])
    }

    @Test("holds at most one connection across rapid event switches (budget invariant)")
    func holdsAtMostOneConnection() {
        let source = FakeStreamSource()
        let manager = makeManager(source)

        // Rapidly switch through many events, as a user tapping around the roster.
        let ids = (0..<25).map { _ in UUID() }
        for id in ids { manager.setActiveEvent(id) }

        // Each switch tore the prior channel down and opened exactly one new one,
        // so the device never holds more than a single Realtime connection — the
        // `connectionsPerActiveDevice == 1` the connection budget plans against.
        #expect(manager.isStreaming)
        #expect(manager.streamingEventID == ids.last)
        #expect(source.openedEvents == ids) // one open per switch, never overlapping
    }

    @Test("repeated foreground/background transitions don't reopen redundantly")
    func transitionsAreIdempotent() {
        let source = FakeStreamSource()
        let manager = makeManager(source)
        manager.setActiveEvent(UUID())

        manager.didEnterBackground()
        manager.didEnterBackground() // no-op
        #expect(!manager.isStreaming)

        manager.didEnterForeground()
        manager.didEnterForeground() // no-op
        #expect(manager.isStreaming)
        #expect(source.openedEvents.count == 2) // initial open + one foreground reopen
    }
}
