import AppIntents

// MARK: - ShiftTimelineIntent

/// Shifts the live SHIFT timeline forward by a specified number of minutes.
///
/// Discoverable in the Shortcuts app and invocable via Siri.
/// When invoked without a value, the system prompts the user for `shiftMinutes`.
struct ShiftTimelineIntent: AppIntent {
    static var title: LocalizedStringResource = "Shift SHIFT Timeline"
    static var description = IntentDescription(
        "Shifts all remaining blocks in the live timeline forward by the specified minutes."
    )

    @Parameter(
        title: "Minutes",
        description: "Number of minutes to shift the timeline forward.",
        default: 10,
        requestValueDialog: "How many minutes would you like to shift?"
    )
    var shiftMinutes: Int

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Subtask 2/3 will wire this to RippleEngine + SwiftData.
        return .result(dialog: "Timeline shifted by \(shiftMinutes) minutes.")
    }
}

// MARK: - App Shortcuts Provider

struct ShiftTimelineShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ShiftTimelineIntent(),
            phrases: [
                "Shift \(.applicationName) timeline",
                "Push \(.applicationName) timeline forward",
                "Delay \(.applicationName) timeline"
            ],
            shortTitle: "Shift Timeline",
            systemImageName: "clock.arrow.circlepath"
        )
    }
}
