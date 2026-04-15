import AppIntents
import SwiftData
import Models
import Engine
import Services

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

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let container = PersistenceController.shared.container
        let context = container.mainContext

        // Fetch live event
        let liveStatus = EventStatus.live
        let descriptor = FetchDescriptor<EventModel>(
            predicate: #Predicate { $0.status == liveStatus }
        )

        guard let event = try context.fetch(descriptor).first else {
            return .result(dialog: "No live event found. Go live first, then try again.")
        }

        // Derive sorted blocks and active block
        let sortedBlocks = event.tracks
            .flatMap(\.blocks)
            .sorted { $0.scheduledStart < $1.scheduledStart }

        guard let activeBlock = sortedBlocks.first(where: { $0.status == .active })
                ?? sortedBlocks.first(where: { $0.status != .completed }) else {
            return .result(dialog: "No active block to shift.")
        }

        // Run the engine
        let delta = TimeInterval(shiftMinutes * 60)
        let engine = RippleEngine()
        let result = engine.recalculate(
            blocks: sortedBlocks,
            changedBlockID: activeBlock.id,
            delta: delta
        )

        switch result.status {
        case .pinnedBlockCannotShift:
            return .result(dialog: "A pinned block prevents this shift.")
        case .circularDependency:
            return .result(dialog: "A circular dependency prevents this shift.")
        case .clean, .hasCollisions, .impossible:
            try context.save()
            return .result(dialog: "Timeline shifted by \(shiftMinutes) minutes.")
        }
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
