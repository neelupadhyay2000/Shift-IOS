//
//  EventModel+LiveModeTransition.swift
//  SHIFTModels
//
//  Pure state-resolution logic for exiting the Live Mode UI.
//
//  The Live Mode screen is a UI state — not an immutable commitment to
//  ship the event today. Users frequently open the dashboard ahead of
//  the event date to rehearse the flow. This transition keeps the
//  persisted `EventStatus` honest about whether the event is actually
//  underway.
//
//  Rules (evaluated in order):
//    1. `.completed` events are terminal and never revert.
//    2. Any status other than `.live` is returned unchanged. This
//       function only *demotes* a `.live` event; it never promotes
//       `.planning` → `.live`. Promotion is a deliberate user action
//       handled elsewhere (entering Live Mode from the event detail).
//    3. `.live` + same calendar day as `now`  → remain `.live`.
//    4. `.live` + different day               → revert to `.planning`
//       (user was rehearsing ahead of / after the scheduled date).
//

import Foundation

public extension EventModel {
    /// Resolves what the persisted `status` should be when the user
    /// dismisses the Live Mode UI.
    ///
    /// This function only **demotes** a `.live` event back to `.planning`
    /// when the calendar day no longer matches. It does not promote any
    /// other status. Callers entering Live Mode are responsible for setting
    /// `status = .live` — this helper simply undoes that if the user was
    /// merely previewing the UI.
    ///
    /// Pure function — does **not** mutate the model. The caller is
    /// responsible for assigning the returned value and saving the
    /// context, which keeps this logic trivially unit-testable and
    /// free of SwiftData side-effects.
    ///
    /// - Parameters:
    ///   - now:      Current date. Injected for deterministic testing.
    ///   - calendar: Calendar to use for same-day comparison. Defaults
    ///               to `.current` so day boundaries follow the user's
    ///               locale and time zone.
    /// - Returns: The `EventStatus` that should be persisted.
    func resolveStatusOnExitLiveMode(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> EventStatus {
        // Terminal state — never revert.
        if status == .completed {
            return .completed
        }

        // Only `.live` is subject to demotion. Every other status is
        // returned as-is to keep this function strictly a demotion step.
        guard status == .live else {
            return status
        }

        // Same calendar day → the event is actually happening.
        if calendar.isDate(date, inSameDayAs: now) {
            return .live
        }

        // Different day → user was previewing. Revert to planning so
        // the event roster, widgets, and watch complications stop
        // advertising a "live" event that isn't.
        return .planning
    }
}
