import XCTest

/// Page object for `EventRosterView` — the app's primary landing screen.
///
/// `rootElement` is the "Events" navigation bar, which is present whenever
/// `EventRosterView` is at the top of the navigation stack.
@MainActor
final class EventRosterScreen: BaseScreen {

    // MARK: - Screen

    override var rootElement: XCUIElement {
        app.navigationBars["Events"]
    }

    // MARK: - Elements

    /// The "+" toolbar button that opens the event-creation sheet.
    var addEventButton: XCUIElement {
        app.buttons[AccessibilityID.Roster.addEventButton]
    }

    /// The segmented status-filter picker (All / Planning / Live / Completed).
    var statusFilterPicker: XCUIElement {
        app.segmentedControls[AccessibilityID.Roster.statusFilter]
    }

    /// The scrollable event list (only present when events exist).
    var eventList: XCUIElement {
        app.scrollViews[AccessibilityID.Roster.eventList]
    }

    /// The "Create Event" button shown in the empty state.
    var createEventButton: XCUIElement {
        app.buttons[AccessibilityID.Roster.createEventButton]
    }

    /// The "No events yet" empty-state label.
    var emptyStateLabel: XCUIElement {
        app.staticTexts["No events yet"]
    }

    // MARK: - Queries

    /// Returns the first static text element whose label matches `title`.
    /// Use this to assert a specific event row is visible after creation.
    func eventCell(title: String) -> XCUIElement {
        app.staticTexts[title]
    }

    // MARK: - Actions

    /// Taps the "+" toolbar button.
    /// - Returns: The `EventCreationScreen` that slides up.
    @discardableResult
    func tapAddEvent() -> EventCreationScreen {
        addEventButton.tap()
        return EventCreationScreen(app: app)
    }

    /// Taps the "Create Event" button in the empty state.
    /// - Returns: The `EventCreationScreen` that slides up.
    @discardableResult
    func tapCreateEventFromEmptyState() -> EventCreationScreen {
        createEventButton.tap()
        return EventCreationScreen(app: app)
    }
}
