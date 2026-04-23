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
//  Rules:
//    1. `.completed` events are terminal and never revert.
//    2. If `now` and `event.date` fall on the same calendar day,
//       the event is genuinely live — keep `.live`.
//    3. Otherwise (user was testing the UI ahead of / after the
//       scheduled date), revert to `.planning`.
//

import Foundation

public extension EventModel {
    /// Resolves what the persisted `status` should be when the user
    /// dismisses the Live Mode UI.
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
