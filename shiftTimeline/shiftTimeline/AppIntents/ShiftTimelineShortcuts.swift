//
//  ShiftTimelineShortcuts.swift
//  shiftTimeline
//
//  Created by Neel Upadhyay on 2026-04-07.
//

import AppIntents

// MARK: - Placeholder Intent

struct ShiftTimelineIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Shift Timeline"
    static var description = IntentDescription("Opens the Shift Timeline app.")

    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

// MARK: - App Shortcuts Provider

struct ShiftTimelineShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ShiftTimelineIntent(),
            phrases: [
                "Open \(.applicationName)",
                "Launch \(.applicationName)"
            ],
            shortTitle: "Open Shift Timeline",
            systemImageName: "clock"
        )
    }
}
