import ActivityKit
import Foundation
import UserNotifications
import os

@MainActor
protocol LiveActivityHandle: AnyObject {
    var attributes: ShiftActivityAttributes { get }
    var contentState: ShiftActivityAttributes.ContentState { get }
    var activityStateUpdates: AsyncStream<LiveActivityState> { get }

    func update(_ content: ActivityContent<ShiftActivityAttributes.ContentState>) async
    func end(
        _ content: ActivityContent<ShiftActivityAttributes.ContentState>,
        dismissalPolicy: LiveActivityDismissalPolicy
    ) async
}

@MainActor
protocol LiveActivityClient {
    func request(
        attributes: ShiftActivityAttributes,
        content: ActivityContent<ShiftActivityAttributes.ContentState>
    ) throws -> LiveActivityHandle

    var activities: [LiveActivityHandle] { get }
}

@MainActor
protocol NotificationScheduling {
    func add(_ request: UNNotificationRequest, completion: (@Sendable (Error?) -> Void)?)
}

@MainActor
protocol LiveActivityAuthorizationChecking {
    var areActivitiesEnabled: Bool { get }
}

enum LiveActivityState {
    case active
    case dismissed
    case ended
    case pending
    case stale
    case unknown
}

enum LiveActivityDismissalPolicy {
    case `default`
    case immediate
}

@MainActor
private final class ActivityKitLiveActivityHandle: LiveActivityHandle {
    private let activity: Activity<ShiftActivityAttributes>

    init(activity: Activity<ShiftActivityAttributes>) {
        self.activity = activity
    }

    var attributes: ShiftActivityAttributes { activity.attributes }

    var contentState: ShiftActivityAttributes.ContentState {
        activity.content.state
    }

    var activityStateUpdates: AsyncStream<LiveActivityState> {
        AsyncStream { continuation in
            let task = Task {
                for await state in activity.activityStateUpdates {
                    switch state {
                    case .active:
                        continuation.yield(.active)
                    case .dismissed:
                        continuation.yield(.dismissed)
                    case .ended:
                        continuation.yield(.ended)
                    case .pending:
                        continuation.yield(.pending)
                    case .stale:
                        continuation.yield(.stale)
                    @unknown default:
                        continuation.yield(.unknown)
                    }
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func update(_ content: ActivityContent<ShiftActivityAttributes.ContentState>) async {
        await activity.update(content)
    }

    func end(
        _ content: ActivityContent<ShiftActivityAttributes.ContentState>,
        dismissalPolicy: LiveActivityDismissalPolicy
    ) async {
        switch dismissalPolicy {
        case .default:
            await activity.end(content, dismissalPolicy: .default)
        case .immediate:
            await activity.end(content, dismissalPolicy: .immediate)
        }
    }
}

@MainActor
private struct ActivityKitLiveActivityClient: LiveActivityClient {
    func request(
        attributes: ShiftActivityAttributes,
        content: ActivityContent<ShiftActivityAttributes.ContentState>
    ) throws -> LiveActivityHandle {
        let activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
        return ActivityKitLiveActivityHandle(activity: activity)
    }

    var activities: [LiveActivityHandle] {
        Activity<ShiftActivityAttributes>.activities.map(ActivityKitLiveActivityHandle.init)
    }
}

@MainActor
private struct UNNotificationCenterScheduler: NotificationScheduling {
    func add(_ request: UNNotificationRequest, completion: (@Sendable (Error?) -> Void)?) {
        UNUserNotificationCenter.current().add(request, withCompletionHandler: completion)
    }
}

@MainActor
private struct ActivityAuthorizationChecker: LiveActivityAuthorizationChecking {
    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }
}

/// Manages the lifecycle of the SHIFT Live Activity (start, update, end).
///
/// Stored as an `@Observable` environment object so both `EventDetailView`
/// (Go Live) and `LiveDashboardView` (advance / shift / exit) can access
/// the running activity.
///
/// ## 8-Hour System Limitation
/// iOS automatically terminates Live Activities after approximately 8 hours,
/// regardless of whether the event is still running. For SHIFT events that
/// exceed this window (e.g. full wedding days), this manager monitors the
/// activity's state via `activityStateUpdates` and attempts an automatic
/// restart while the app process is running. If restart fails (e.g.
/// ActivityKit budget exhausted), a local notification prompts the user to
/// reopen the live session.
@MainActor
@Observable
final class LiveActivityManager {

    nonisolated private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.shift",
        category: "LiveActivityManager"
    )

    /// Notification category used for the "restart Live Activity" prompt.
    static let restartNotificationCategory = "SHIFT_LIVE_ACTIVITY_RESTART"

    private let activityClient: LiveActivityClient
    private let notificationScheduler: NotificationScheduling
    private let authorizationChecker: LiveActivityAuthorizationChecking

    /// The currently running Live Activity, if any.
    private(set) var currentActivity: LiveActivityHandle?

    /// The event ID associated with the current Live Activity, used for
    /// deep-linking when scheduling the restart notification.
    private(set) var activeEventID: UUID?

    /// The most recent content state, cached so we can restart with the
    /// correct block data after an 8-hour system kill.
    private var lastContentState: ShiftActivityAttributes.ContentState?

    /// The attributes (event title) of the current activity, cached for restart.
    private var lastAttributes: ShiftActivityAttributes?

    /// Task monitoring the activity state for unexpected dismissals.
    private var monitorTask: Task<Void, Never>?

    init(
        activityClient: LiveActivityClient? = nil,
        notificationScheduler: NotificationScheduling? = nil,
        authorizationChecker: LiveActivityAuthorizationChecking? = nil
    ) {
        self.activityClient = activityClient ?? ActivityKitLiveActivityClient()
        self.notificationScheduler = notificationScheduler ?? UNNotificationCenterScheduler()
        self.authorizationChecker = authorizationChecker ?? ActivityAuthorizationChecker()
    }

    // MARK: - Start

    /// Starts a new Live Activity for the given event and first active block.
    ///
    /// Call this when `event.status` transitions to `.live`.
    /// If Live Activities are disabled in Settings, this silently no-ops.
    func start(
        eventTitle: String,
        currentBlockTitle: String,
        blockEndTime: Date,
        nextBlockTitle: String? = nil,
        sunsetTime: Date? = nil,
        eventID: UUID? = nil
    ) {
        guard authorizationChecker.areActivitiesEnabled else {
            Self.logger.info("Live Activities disabled — skipping start")
            return
        }

        // End any lingering activity from a previous session.
        if let oldActivity = currentActivity {
            let oldState = ShiftActivityAttributes.ContentState(
                currentBlockTitle: String(localized: "Event Complete"),
                endTime: .now
            )
            let oldContent = ActivityContent(state: oldState, staleDate: nil)
            Task {
                await oldActivity.end(oldContent, dismissalPolicy: .immediate)
            }
            currentActivity = nil
        }

        let attributes = ShiftActivityAttributes(eventTitle: eventTitle)
        let state = ShiftActivityAttributes.ContentState(
            currentBlockTitle: currentBlockTitle,
            endTime: blockEndTime,
            nextBlockTitle: nextBlockTitle,
            sunsetTime: sunsetTime
        )
        let content = ActivityContent(state: state, staleDate: nil)

        do {
            currentActivity = try activityClient.request(
                attributes: attributes,
                content: content
            )
            lastAttributes = attributes
            lastContentState = state
            activeEventID = eventID
            Self.logger.info("Live Activity started for \"\(eventTitle)\"")
            startMonitoring()
        } catch {
            Self.logger.error("Failed to start Live Activity: \(error.localizedDescription)")
        }
    }

    // MARK: - Update

    /// Pushes a new content state to the running Live Activity.
    func update(
        currentBlockTitle: String,
        blockEndTime: Date,
        nextBlockTitle: String? = nil,
        sunsetTime: Date? = nil
    ) {
        guard let activity = currentActivity else { return }

        let state = ShiftActivityAttributes.ContentState(
            currentBlockTitle: currentBlockTitle,
            endTime: blockEndTime,
            nextBlockTitle: nextBlockTitle,
            sunsetTime: sunsetTime
        )
        let content = ActivityContent(state: state, staleDate: nil)
        lastContentState = state

        Task {
            await activity.update(content)
            Self.logger.info("Live Activity updated — block: \"\(currentBlockTitle)\"")
        }
    }

    // MARK: - End

    /// Ends the Live Activity with a final state, allowing it to linger
    /// briefly on the Lock Screen before dismissing.
    func end(
        finalBlockTitle: String? = nil,
        blockEndTime: Date = .now
    ) {
        guard let activity = currentActivity else { return }

        let state = ShiftActivityAttributes.ContentState(
            currentBlockTitle: finalBlockTitle ?? String(localized: "Event Complete"),
            endTime: blockEndTime
        )
        let content = ActivityContent(state: state, staleDate: nil)

        monitorTask?.cancel()
        monitorTask = nil

        Task {
            await activity.end(content, dismissalPolicy: .default)
            Self.logger.info("Live Activity ended")
        }
        currentActivity = nil
        lastContentState = nil
        lastAttributes = nil
        activeEventID = nil
    }

    /// Ends the Live Activity immediately without lingering.
    func endImmediately() async {
        guard let activity = currentActivity else { return }

        monitorTask?.cancel()
        monitorTask = nil

        let state = ShiftActivityAttributes.ContentState(
            currentBlockTitle: String(localized: "Event Complete"),
            endTime: .now
        )
        let content = ActivityContent(state: state, staleDate: nil)
        await activity.end(content, dismissalPolicy: .immediate)
        currentActivity = nil
        lastContentState = nil
        lastAttributes = nil
        activeEventID = nil
    }

    // MARK: - Recovery

    /// Attempts to reclaim an existing Live Activity after an app relaunch
    /// (e.g. after the 8-hour system kill). Returns `true` if one was found.
    @discardableResult
    func reclaimExistingActivity() -> Bool {
        let running = activityClient.activities
        if let existing = running.first {
            currentActivity = existing
            lastAttributes = existing.attributes
            lastContentState = existing.contentState
            Self.logger.info("Reclaimed existing Live Activity")
            startMonitoring()
            return true
        }
        return false
    }

    // MARK: - 8-Hour Auto-Kill Detection & Restart

    /// Monitors `activityStateUpdates` on the current activity. When the
    /// system dismisses the activity (8-hour timeout) while `lastContentState`
    /// is still set (meaning the event hasn't ended normally), we attempt an
    /// automatic restart.
    ///
    /// - Note: iOS terminates Live Activities after ~8 hours regardless of
    ///   event state. This is a platform limitation that cannot be avoided.
    private func startMonitoring() {
        monitorTask?.cancel()

        guard let activity = currentActivity else { return }

        monitorTask = Task { [weak self] in
            for await activityState in activity.activityStateUpdates {
                guard !Task.isCancelled else { return }

                guard activityState == .dismissed else { continue }
                self?.handleDismissedActivity()
                return // Exit the loop — restart starts a new monitor.
            }
        }
    }

    private func handleDismissedActivity() {
        // The system killed the activity. Check whether we still have cached
        // state (i.e. event is still live).
        guard let attributes = lastAttributes,
              let state = lastContentState else {
            return
        }

        Self.logger.warning("Live Activity dismissed by system — attempting restart")
        currentActivity = nil
        attemptRestart(attributes: attributes, state: state)
    }

    /// Tries to start a fresh Live Activity with the cached state.
    /// If ActivityKit's budget is exhausted, falls back to a local notification.
    private func attemptRestart(
        attributes: ShiftActivityAttributes,
        state: ShiftActivityAttributes.ContentState
    ) {
        guard authorizationChecker.areActivitiesEnabled else {
            scheduleRestartNotification()
            return
        }

        let content = ActivityContent(state: state, staleDate: nil)

        do {
            currentActivity = try activityClient.request(
                attributes: attributes,
                content: content
            )
            Self.logger.info("Live Activity restarted after system kill")
            startMonitoring()
        } catch {
            // ActivityKit budget exhausted or other system error — fall back
            // to a local notification prompting the user to reopen.
            Self.logger.error(
                "Failed to restart Live Activity (budget exhausted?): \(error.localizedDescription)"
            )
            scheduleRestartNotification()
        }
    }

    /// Schedules a local notification asking the user to tap to restart
    /// the live timeline. The notification deep-links to `shift://live/{id}`.
    private func scheduleRestartNotification() {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "SHIFT")
        content.body = String(localized: "Tap to restart live timeline")
        content.sound = .default
        content.categoryIdentifier = Self.restartNotificationCategory

        if let eventID = activeEventID {
            content.userInfo = ["eventID": eventID.uuidString, "isLiveRestart": true]
        }

        let request = UNNotificationRequest(
            identifier: "shift-live-activity-restart",
            content: content,
            trigger: nil // Fire immediately.
        )

        notificationScheduler.add(request) { error in
            if let error {
                Self.logger.error("Failed to schedule restart notification: \(error.localizedDescription)")
            } else {
                Self.logger.info("Scheduled restart notification for live event")
            }
        }
    }
}
