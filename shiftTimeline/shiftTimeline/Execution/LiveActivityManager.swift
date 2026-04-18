import ActivityKit
import Foundation
import UserNotifications
import os

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
/// restart. If the restart fails (e.g. ActivityKit budget exhausted or app
/// terminated), a local notification prompts the user to reopen the app.
@Observable
final class LiveActivityManager: @unchecked Sendable {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.shift",
        category: "LiveActivityManager"
    )

    /// Notification category used for the "restart Live Activity" prompt.
    static let restartNotificationCategory = "SHIFT_LIVE_ACTIVITY_RESTART"

    /// The currently running Live Activity, if any.
    private(set) var currentActivity: Activity<ShiftActivityAttributes>?

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
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            Self.logger.info("Live Activities disabled — skipping start")
            return
        }

        // End any lingering activity from a previous session.
        if currentActivity != nil {
            Task { await endImmediately() }
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
            currentActivity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
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
        finalBlockTitle: String = "Event Complete",
        blockEndTime: Date = .now
    ) {
        guard let activity = currentActivity else { return }

        let state = ShiftActivityAttributes.ContentState(
            currentBlockTitle: finalBlockTitle,
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
            currentBlockTitle: "Event Complete",
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
        let running = Activity<ShiftActivityAttributes>.activities
        if let existing = running.first {
            currentActivity = existing
            lastAttributes = existing.attributes
            lastContentState = existing.content.state
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

                if activityState == .dismissed {
                    // The system killed the activity. Check whether
                    // we still have cached state (i.e. event is still live).
                    guard let self,
                          let attributes = self.lastAttributes,
                          let state = self.lastContentState else {
                        return
                    }

                    Self.logger.warning(
                        "Live Activity dismissed by system — attempting restart"
                    )

                    await MainActor.run {
                        self.currentActivity = nil
                        self.attemptRestart(attributes: attributes, state: state)
                    }
                    return // Exit the loop — restart starts a new monitor.
                }
            }
        }
    }

    /// Tries to start a fresh Live Activity with the cached state.
    /// If ActivityKit's budget is exhausted, falls back to a local notification.
    @MainActor
    private func attemptRestart(
        attributes: ShiftActivityAttributes,
        state: ShiftActivityAttributes.ContentState
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            scheduleRestartNotification()
            return
        }

        let content = ActivityContent(state: state, staleDate: nil)

        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
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
        content.title = "SHIFT"
        content.body = "Tap to restart live timeline"
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

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Self.logger.error("Failed to schedule restart notification: \(error.localizedDescription)")
            } else {
                Self.logger.info("Scheduled restart notification for live event")
            }
        }
    }
}
