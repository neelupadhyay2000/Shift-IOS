import XCTest

/// Page object for `CreateEventSheet` — the modal form for creating a new event.
///
/// `rootElement` is the "New Event" navigation bar that appears when the sheet
/// has fully presented.
@MainActor
final class EventCreationScreen: BaseScreen {

    // MARK: - Screen

    override var rootElement: XCUIElement {
        app.navigationBars["New Event"]
    }

    // MARK: - Elements

    /// The required event-title text field.
    var titleField: XCUIElement {
        app.textFields[AccessibilityID.EventCreation.titleField]
    }

    /// The date picker for the event date.
    var datePicker: XCUIElement {
        app.datePickers[AccessibilityID.EventCreation.datePicker]
    }

    /// The "Cancel" toolbar button (dismisses without saving).
    var cancelButton: XCUIElement {
        app.buttons[AccessibilityID.EventCreation.cancelButton]
    }

    /// The "Create" toolbar button (disabled until a non-empty title is entered).
    var createButton: XCUIElement {
        app.buttons[AccessibilityID.EventCreation.createButton]
    }

    // MARK: - Actions

    /// Types `text` into the title field.
    /// - Returns: `self` for chaining.
    @discardableResult
    func enterTitle(_ text: String) -> Self {
        titleField.tap()
        titleField.typeText(text)
        return self
    }

    /// Clears and re-types the title field.
    @discardableResult
    func replaceTitle(with text: String) -> Self {
        titleField.tap()
        titleField.clearAndTypeText(text)
        return self
    }

    /// Taps "Create" and waits for the sheet to dismiss.
    /// - Returns: The `EventRosterScreen` that is revealed.
    @discardableResult
    func tapCreate() -> EventRosterScreen {
        createButton.tap()
        return EventRosterScreen(app: app)
    }

    /// Taps "Cancel" and waits for the sheet to dismiss.
    /// - Returns: The `EventRosterScreen` that is revealed.
    @discardableResult
    func tapCancel() -> EventRosterScreen {
        cancelButton.tap()
        return EventRosterScreen(app: app)
    }
}

// MARK: - XCUIElement convenience

private extension XCUIElement {
    /// Selects all text then types replacement text, mimicking a clear+type sequence.
    func clearAndTypeText(_ text: String) {
        guard let currentValue = value as? String, !currentValue.isEmpty else {
            typeText(text)
            return
        }
        let selectAll = XCUIApplication().menuItems["Select All"]
        if selectAll.waitForExistence(timeout: 1) {
            selectAll.tap()
        } else {
            coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1.2)
            if selectAll.waitForExistence(timeout: 1) { selectAll.tap() }
        }
        typeText(text)
    }
}
