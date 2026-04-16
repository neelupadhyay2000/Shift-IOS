import Foundation
import Testing
import SwiftData
import WatchConnectivity
import Models
import Engine
import Services

@testable import shiftTimeline

// MARK: - MockWatchSession

/// Captures all calls made to the session for assertion in tests.
@MainActor
final class MockWatchSession: WatchSessionProtocol {
    var isReachable: Bool = true
    var delegate: WCSessionDelegate?

    private(set) var activateCalled = false
    private(set) var lastSentContext: [String: Any]?
    private(set) var sentContextCount = 0

    func activate() {
        activateCalled = true
    }

    func updateApplicationContext(_ applicationContext: [String: Any]) throws {
        lastSentContext = applicationContext
        sentContextCount += 1
    }

    func sendMessage(
        _ message: [String: Any],
        replyHandler: (([String: Any]) -> Void)?,
        errorHandler: ((any Error) -> Void)?
    ) {
        // Not used in iOS-side tests (Watch sends messages to iPhone, not vice versa).
    }
}

// MARK: - Tests

@Suite(.serialized)
struct WatchSessionManagerTests {

    // MARK: - Test Container

    @MainActor
    private static func makeContainer() throws -> ModelContainer {
        try PersistenceController.forTesting()
    }

    // MARK: - Helpers

    @MainActor
    private static func insertLiveEvent(
        into container: ModelContainer,
        blockCount: Int = 3,
        sunsetTime: Date? = nil
    ) -> EventModel {
        let context = container.mainContext
        let now = Date.now

        let event = EventModel(
            title: "Test Event",
            date: now,
            latitude: 40.7128,
            longitude: -74.0060,
            sunsetTime: sunsetTime,
            status: .live
        )
        context.insert(event)

        let track = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true, event: event)
        context.insert(track)

        for i in 0..<blockCount {
            let start = now.addingTimeInterval(TimeInterval(i * 1800))
            let block = TimeBlockModel(
                title: "Block \(i + 1)",
                scheduledStart: start,
                duration: 1800
            )
            block.status = i == 0 ? .active : .upcoming
            block.track = track
            context.insert(block)
        }

        try? context.save()
        return event
    }

    // MARK: - Activation

    @Test @MainActor func activateSetsDelegate() throws {
        let session = MockWatchSession()
        let container = try Self.makeContainer()
        let manager = WatchSessionManager(session: session, container: container)

        manager.activate()

        #expect(session.activateCalled)
        #expect(session.delegate != nil)
    }

    // MARK: - Send Context

    @Test @MainActor func sendCurrentContextWithLiveEventPushesContext() throws {
        let session = MockWatchSession()
        let container = try Self.makeContainer()
        let sunset = Date.now.addingTimeInterval(7200)
        _ = Self.insertLiveEvent(into: container, sunsetTime: sunset)

        let manager = WatchSessionManager(session: session, container: container)
        manager.sendCurrentContext()

        #expect(session.sentContextCount == 1)
        #expect(session.lastSentContext?["activeBlockTitle"] as? String == "Block 1")
        #expect(session.lastSentContext?["eventTitle"] as? String == "Test Event")
        #expect(session.lastSentContext?["isLive"] as? Bool == true)
        #expect(session.lastSentContext?["nextBlockTitle"] as? String == "Block 2")
        #expect(session.lastSentContext?["sunsetTime"] != nil)
        #expect(manager.lastSentContext?.activeBlockTitle == "Block 1")
    }

    @Test @MainActor func sendCurrentContextWithNoLiveEventIsNoOp() throws {
        let session = MockWatchSession()
        let container = try Self.makeContainer()
        // No event inserted — context should not be sent.

        let manager = WatchSessionManager(session: session, container: container)
        manager.sendCurrentContext()

        #expect(session.sentContextCount == 0)
        #expect(manager.lastSentContext == nil)
    }

    @Test @MainActor func sendCurrentContextWithPlanningEventIsNoOp() throws {
        let session = MockWatchSession()
        let container = try Self.makeContainer()

        // Insert a planning event (not live).
        let event = EventModel(
            title: "Planning Event",
            date: .now,
            latitude: 0,
            longitude: 0,
            status: .planning
        )
        container.mainContext.insert(event)
        try? container.mainContext.save()

        let manager = WatchSessionManager(session: session, container: container)
        manager.sendCurrentContext()

        #expect(session.sentContextCount == 0)
    }

    @Test @MainActor func sendContextForEventPushesExplicitContext() throws {
        let session = MockWatchSession()
        let container = try Self.makeContainer()
        let event = Self.insertLiveEvent(into: container)

        let blocks = (event.tracks ?? []).flatMap { $0.blocks ?? [] }
            .sorted(by: { $0.scheduledStart < $1.scheduledStart })
        let active = blocks[0]
        let next = blocks[1]

        let manager = WatchSessionManager(session: session, container: container)
        manager.sendContext(for: event, activeBlock: active, nextBlock: next)

        #expect(session.sentContextCount == 1)
        #expect(session.lastSentContext?["activeBlockTitle"] as? String == "Block 1")
        #expect(session.lastSentContext?["nextBlockTitle"] as? String == "Block 2")
    }

    // MARK: - Handle Shift Command

    @Test @MainActor func handleShiftCommandShiftsBlocksAndReplies() throws {
        let session = MockWatchSession()
        let container = try Self.makeContainer()
        let event = Self.insertLiveEvent(into: container)

        let blocks = (event.tracks ?? []).flatMap { $0.blocks ?? [] }
            .sorted(by: { $0.scheduledStart < $1.scheduledStart })
        let originalBlock2Start = blocks[1].scheduledStart

        let manager = WatchSessionManager(session: session, container: container)

        var reply: [String: Any]?
        let message: [String: Any] = ["command": "shift", "minutes": 5]

        manager.handleMessage(message) { r in
            reply = r
        }

        #expect(reply != nil)
        #expect(reply?["error"] == nil)
        #expect(reply?["activeBlockTitle"] as? String == "Block 1")
        #expect(manager.lastReceivedCommand?.action == .shift)
        #expect(manager.lastReceivedCommand?.deltaMinutes == 5)

        // Verify the shift was applied — Block 2 should have moved forward by 5 min.
        let updatedBlocks = (event.tracks ?? []).flatMap { $0.blocks ?? [] }
            .sorted(by: { $0.scheduledStart < $1.scheduledStart })
        let shiftDelta = updatedBlocks[1].scheduledStart.timeIntervalSince(originalBlock2Start)
        #expect(abs(shiftDelta - 300) < 1, "Block 2 should shift forward by 5 minutes")
    }

    @Test @MainActor func handleShiftWithZeroDeltaReturnsError() throws {
        let session = MockWatchSession()
        let container = try Self.makeContainer()
        _ = Self.insertLiveEvent(into: container)

        let manager = WatchSessionManager(session: session, container: container)

        var reply: [String: Any]?
        manager.handleMessage(["command": "shift", "minutes": 0]) { r in
            reply = r
        }

        #expect(reply?["error"] as? String == "zero_delta")
    }

    @Test @MainActor func handleShiftWithNoLiveEventReturnsError() throws {
        let session = MockWatchSession()
        let container = try Self.makeContainer()
        // No event inserted.

        let manager = WatchSessionManager(session: session, container: container)

        var reply: [String: Any]?
        manager.handleMessage(["command": "shift", "minutes": 5]) { r in
            reply = r
        }

        #expect(reply?["error"] as? String == "no_live_event")
    }

    // MARK: - Handle Complete Block Command

    @Test @MainActor func handleCompleteBlockAdvancesToNext() throws {
        let session = MockWatchSession()
        let container = try Self.makeContainer()
        let event = Self.insertLiveEvent(into: container)

        let manager = WatchSessionManager(session: session, container: container)

        var reply: [String: Any]?
        manager.handleMessage(["command": "completeBlock"]) { r in
            reply = r
        }

        #expect(reply != nil)
        #expect(reply?["error"] == nil)
        #expect(reply?["activeBlockTitle"] as? String == "Block 2")
        #expect(reply?["isLive"] as? Bool == true)

        // Verify Block 1 is completed, Block 2 is active.
        let blocks = (event.tracks ?? []).flatMap { $0.blocks ?? [] }
            .sorted(by: { $0.scheduledStart < $1.scheduledStart })
        #expect(blocks[0].status == .completed)
        #expect(blocks[1].status == BlockStatus.active)
    }

    @Test @MainActor func handleCompleteLastBlockCompletesEvent() throws {
        let session = MockWatchSession()
        let container = try Self.makeContainer()
        let event = Self.insertLiveEvent(into: container, blockCount: 1)

        let manager = WatchSessionManager(session: session, container: container)

        var reply: [String: Any]?
        manager.handleMessage(["command": "completeBlock"]) { r in
            reply = r
        }

        #expect(reply != nil)
        #expect(event.status == .completed)
    }

    // MARK: - Unrecognized Message

    @Test @MainActor func handleUnrecognizedMessageReturnsError() throws {
        let session = MockWatchSession()
        let container = try Self.makeContainer()
        let manager = WatchSessionManager(session: session, container: container)

        var reply: [String: Any]?
        manager.handleMessage(["garbage": "data"]) { r in
            reply = r
        }

        #expect(reply?["error"] as? String == "unrecognized_command")
    }

    // MARK: - Activation Sends Context

    @Test @MainActor func handleActivationCompleteSendsContext() throws {
        let session = MockWatchSession()
        let container = try Self.makeContainer()
        _ = Self.insertLiveEvent(into: container)

        let manager = WatchSessionManager(session: session, container: container)
        manager.handleActivationComplete()

        #expect(session.sentContextCount == 1)
        #expect(manager.lastSentContext?.activeBlockTitle == "Block 1")
    }

    @Test @MainActor func handleActivationCompleteWithNoEventIsNoOp() throws {
        let session = MockWatchSession()
        let container = try Self.makeContainer()
        // No event.

        let manager = WatchSessionManager(session: session, container: container)
        manager.handleActivationComplete()

        #expect(session.sentContextCount == 0)
    }
}
