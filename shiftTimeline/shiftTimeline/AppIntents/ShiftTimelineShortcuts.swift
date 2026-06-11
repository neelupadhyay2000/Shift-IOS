import AppIntents
import SwiftData
import WatchConnectivity
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

    /// Valid range matches the in-app QuickShiftSheet (1…120 minutes).
    static let validRange = 1...120

    @Parameter(
        title: "Minutes",
        description: "Number of minutes to shift the timeline forward (1–120).",
        default: 10,
        requestValueDialog: "How many minutes would you like to shift?"
    )
    var shiftMinutes: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Input validation
        guard Self.validRange.contains(shiftMinutes) else {
            return .result(
                dialog: IntentDialog("Please choose between 1 and 120 minutes.")
            )
        }

        let container = PersistenceController.shared.container
        let context = container.mainContext

        // Fetch all events and filter in-memory — #Predicate with enum
        // comparison can crash at runtime in SwiftData.
        let allEvents: [EventModel]
        do {
            allEvents = try context.fetch(FetchDescriptor<EventModel>())
        } catch {
            return .result(
                dialog: IntentDialog("Could not access event data. Please try again.")
            )
        }

        guard let event = allEvents.first(where: { $0.status == .live }) else {
            return .result(
                dialog: IntentDialog("No live event found. Go live first, then try again.")
            )
        }

        // Derive sorted blocks and active block
        let sortedBlocks = (event.tracks ?? [])
            .flatMap { $0.blocks ?? [] }
            .sorted { $0.scheduledStart < $1.scheduledStart }

        guard let activeBlock = sortedBlocks.first(where: { $0.status == .active })
                ?? sortedBlocks.first(where: { $0.status != .completed }) else {
            return .result(
                dialog: IntentDialog("No active block to shift.")
            )
        }

        // Run the full extension pipeline (extend → ripple → collide →
        // compress) so a Siri shift commits the same resolved timeline as an
        // in-app shift: live +x extends the running block, never moves it.
        let delta = TimeInterval(shiftMinutes * 60)
        let engine = RippleEngine()
        let result = engine.applyExtension(
            blocks: sortedBlocks,
            activeBlockID: activeBlock.id,
            delta: delta
        )

        switch result.status {
        case .pinnedBlockCannotShift:
            return .result(
                dialog: IntentDialog("A pinned block prevents this shift.")
            )
        case .circularDependency:
            return .result(
                dialog: IntentDialog("A circular dependency prevents this shift.")
            )
        case .exceedsAvailableSlack:
            let maximum = engine.maximumExtension(blocks: sortedBlocks, activeBlockID: activeBlock.id) ?? 0
            let maxMinutes = Int(maximum / 60)
            if maxMinutes > 0 {
                return .result(
                    dialog: IntentDialog(
                        "You can extend by up to \(maxMinutes) minutes before the next pinned block."
                    )
                )
            }
            return .result(
                dialog: IntentDialog("The next pinned block leaves no room to extend.")
            )
        case .clean, .hasCollisions, .impossible:
            VendorShiftNotifier.applyThresholdNotifications(
                event: event,
                blocks: result.blocks
            )
            // Propagate the ack reset to Supabase (vendors re-acknowledge).
            let vendorResets = VendorShiftResetService.resets(for: event)
            Task { await VendorShiftResetService.live.pushReset(vendorResets) }
            PersistenceController.recordShift(
                deltaMinutes: shiftMinutes,
                triggeredBy: .manual,
                sourceBlock: activeBlock,
                event: event,
                into: context
            )
            do {
                try context.save()
            } catch {
                return .result(
                    dialog: IntentDialog("Timeline was shifted but could not be saved. Please try again.")
                )
            }
            WatchSessionManager.pushCurrentContext()
            return .result(
                dialog: IntentDialog("Timeline shifted by \(shiftMinutes) minutes.")
            )
        }
    }
}

// MARK: - App Shortcuts Provider

struct ShiftTimelineShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ShiftTimelineIntent(),
            phrases: [
                "Shift my \(.applicationName) timeline",
                "Shift my timeline in \(.applicationName)",
                "Push \(.applicationName) timeline forward",
                "Delay \(.applicationName) timeline"
            ],
            shortTitle: "Shift Timeline",
            systemImageName: "clock.arrow.circlepath"
        )
    }
}
