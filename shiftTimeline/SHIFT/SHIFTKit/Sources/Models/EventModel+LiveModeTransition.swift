//
//  EventModel+LiveModeTransition.swift
//  SHIFTModels
//
//  Pure state-resolution logic for exiting the Live Mode UI.
//

import Foundation

public extension EventModel {
    /// Returns the `EventStatus` to persist when the user dismisses Live Mode.
    /// Demotes `.live` → `.planning` if the event date is on a different calendar day (i.e. user was rehearsing).
    /// Pure function — does not mutate the model.
    func resolveStatusOnExitLiveMode(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> EventStatus {
        // Terminal state — never revert.
        if status == .completed {
            return .completed
        }

        // Only demote `.live`; return every other status unchanged.
        guard status == .live else {
            return status
        }

        if calendar.isDate(date, inSameDayAs: now) {
            return .live
        }

        // Different day — user was previewing. Revert to planning.
        return .planning
    }
}
