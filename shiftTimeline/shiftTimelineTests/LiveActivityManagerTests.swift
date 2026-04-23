import ActivityKit
import Foundation
import Testing
import UserNotifications

@testable import shiftTimeline

@MainActor
final class MockLiveActivityHandle: LiveActivityHandle {
    let attributes: ShiftActivityAttributes
    private(set) var contentState: ShiftActivityAttributes.ContentState

    private(set) var updateCount = 0
    private(set) var endCount = 0
    private(set) var lastDismissalPolicy: LiveActivityDismissalPolicy?

    private let stream: AsyncStream<LiveActivityState>
    private var continuation: AsyncStream<LiveActivityState>.Continuation?

    init(
        attributes: ShiftActivityAttributes,
        contentState: ShiftActivityAttributes.ContentState
    ) {
        self.attributes = attributes
        self.contentState = contentState

        var c: AsyncStream<LiveActivityState>.Continuation?
        self.stream = AsyncStream { continuation in
            c = continuation
        }
        self.continuation = c
    }

    var activityStateUpdates: AsyncStream<LiveActivityState> { stream }

    func update(_ content: ActivityContent<ShiftActivityAttributes.ContentState>) async {
        updateCount += 1
        contentState = content.state
    }

    func end(
        _ content: ActivityContent<ShiftActivityAttributes.ContentState>,
        dismissalPolicy: LiveActivityDismissalPolicy
    ) async {
        endCount += 1
        lastDismissalPolicy = dismissalPolicy
        contentState = content.state
    }

    func emit(_ state: LiveActivityState) {
        continuation?.yield(state)
    }
}

@MainActor
final class MockLiveActivityClient: LiveActivityClient {
    var queuedActivities: [MockLiveActivityHandle] = []
    var shouldFailRequest = false
    private(set) var requestCount = 0

    var activities: [LiveActivityHandle] {
        queuedActivities
    }

    func request(
        attributes: ShiftActivityAttributes,
        content: ActivityContent<ShiftActivityAttributes.ContentState>
    ) throws -> LiveActivityHandle {
        requestCount += 1

        if shouldFailRequest {
            struct RequestFailure: Error {}
            throw RequestFailure()
        }

        if queuedActivities.isEmpty {
            let created = MockLiveActivityHandle(attributes: attributes, contentState: content.state)
            queuedActivities.append(created)
        }

        return queuedActivities.removeFirst()
    }
}

@MainActor
final class MockNotificationScheduler: NotificationScheduling {
    private(set) var requests: [UNNotificationRequest] = []

    func add(_ request: UNNotificationRequest, completion: (@Sendable (Error?) -> Void)?) {
        requests.append(request)
        completion?(nil)
    }
}

struct MockAuthorizationChecker: LiveActivityAuthorizationChecking {
    let areActivitiesEnabled: Bool
}

@Suite(.serialized)
struct LiveActivityManagerTests {

    @Test @MainActor
    func startEndsOnlyPreviousActivityWhenReplacingCurrent() async {
        let attributes = ShiftActivityAttributes(eventTitle: "Wedding")
        let state = ShiftActivityAttributes.ContentState(
            currentBlockTitle: "Ceremony",
            endTime: .now
        )

        let oldActivity = MockLiveActivityHandle(attributes: attributes, contentState: state)
        let newActivity = MockLiveActivityHandle(attributes: attributes, contentState: state)

        let client = MockLiveActivityClient()
        client.queuedActivities = [oldActivity, newActivity]

        let manager = LiveActivityManager(
            activityClient: client,
            notificationScheduler: MockNotificationScheduler(),
            authorizationChecker: MockAuthorizationChecker(areActivitiesEnabled: true)
        )

        manager.start(eventTitle: "Wedding", currentBlockTitle: "Ceremony", blockEndTime: .now)
        manager.start(eventTitle: "Wedding", currentBlockTitle: "Reception", blockEndTime: .now)

        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(oldActivity.endCount == 1)
        #expect(oldActivity.lastDismissalPolicy == .immediate)
        #expect(newActivity.endCount == 0)
    }

    @Test @MainActor
    func dismissedActivityAttemptsAutomaticRestart() async {
        let attributes = ShiftActivityAttributes(eventTitle: "Wedding")
        let state = ShiftActivityAttributes.ContentState(
            currentBlockTitle: "Ceremony",
            endTime: .now
        )

        let initial = MockLiveActivityHandle(attributes: attributes, contentState: state)
        let restarted = MockLiveActivityHandle(attributes: attributes, contentState: state)

        let client = MockLiveActivityClient()
        client.queuedActivities = [initial, restarted]

        let manager = LiveActivityManager(
            activityClient: client,
            notificationScheduler: MockNotificationScheduler(),
            authorizationChecker: MockAuthorizationChecker(areActivitiesEnabled: true)
        )

        manager.start(eventTitle: "Wedding", currentBlockTitle: "Ceremony", blockEndTime: .now)
        initial.emit(.dismissed)

        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(client.requestCount == 2)
        let current = manager.currentActivity as? MockLiveActivityHandle
        #expect(current === restarted)
    }

    @Test @MainActor
    func restartFailureSchedulesLocalNotificationFallback() async throws {
        let attributes = ShiftActivityAttributes(eventTitle: "Wedding")
        let state = ShiftActivityAttributes.ContentState(
            currentBlockTitle: "Ceremony",
            endTime: .now
        )

        let initial = MockLiveActivityHandle(attributes: attributes, contentState: state)
        let client = MockLiveActivityClient()
        client.queuedActivities = [initial]

        let scheduler = MockNotificationScheduler()

        let manager = LiveActivityManager(
            activityClient: client,
            notificationScheduler: scheduler,
            authorizationChecker: MockAuthorizationChecker(areActivitiesEnabled: true)
        )

        manager.start(
            eventTitle: "Wedding",
            currentBlockTitle: "Ceremony",
            blockEndTime: .now,
            eventID: UUID()
        )

        client.shouldFailRequest = true
        initial.emit(.dismissed)

        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(scheduler.requests.count == 1)
        let request = try #require(scheduler.requests.first)
        #expect(request.content.body == String(localized: "Tap to restart live timeline"))
    }
}
