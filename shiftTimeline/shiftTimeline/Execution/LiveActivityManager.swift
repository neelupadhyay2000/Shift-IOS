import ActivityKit
import Foundation
import os

/// Manages the lifecycle of the SHIFT Live Activity (start, update, end).
///
/// Stored as an `@Observable` environment object so both `EventDetailView`
/// (Go Live) and `LiveDashboardView` (advance / shift / exit) can access
/// the running activity.
@Observable
final class LiveActivityManager: @unchecked Sendable {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.shift",
        category: "LiveActivityManager"
    )

    /// The currently running Live Activity, if any.
    private(set) var currentActivity: Activity<ShiftActivityAttributes>?

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
        sunsetTime: Date? = nil
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
            Self.logger.info("Live Activity started for \"\(eventTitle)\"")
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

        Task {
            await activity.end(content, dismissalPolicy: .default)
            Self.logger.info("Live Activity ended")
        }
        currentActivity = nil
    }

    /// Ends the Live Activity immediately without lingering.
    func endImmediately() async {
        guard let activity = currentActivity else { return }

        let state = ShiftActivityAttributes.ContentState(
            currentBlockTitle: "Event Complete",
            endTime: .now
        )
        let content = ActivityContent(state: state, staleDate: nil)
        await activity.end(content, dismissalPolicy: .immediate)
        currentActivity = nil
    }

    // MARK: - Recovery

    /// Attempts to reclaim an existing Live Activity after an app relaunch
    /// (e.g. after the 8-hour system kill). Returns `true` if one was found.
    @discardableResult
    func reclaimExistingActivity() -> Bool {
        let running = Activity<ShiftActivityAttributes>.activities
        if let existing = running.first {
            currentActivity = existing
            Self.logger.info("Reclaimed existing Live Activity")
            return true
        }
        return false
    }
}
