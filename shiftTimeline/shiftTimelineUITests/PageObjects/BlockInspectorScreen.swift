import XCTest

/// Page object for `BlockInspectorView` in sheet mode (iPhone).
///
/// Sheet mode wraps the form in a `NavigationStack` with title "Edit Block"
/// (or "Block Details" for read-only). The root element anchors on the nav bar
/// so `waitForExistence` correctly waits for the sheet to fully present.
@MainActor
final class BlockInspectorScreen: BaseScreen {

    override var rootElement: XCUIElement {
        app.navigationBars["Edit Block"]
    }

    // MARK: - Elements

    var titleField: XCUIElement {
        app.textFields[AccessibilityID.Inspector.titleField]
    }

    var durationPicker: XCUIElement {
        app.segmentedControls[AccessibilityID.Inspector.durationField]
    }

    var saveButton: XCUIElement {
        app.buttons[AccessibilityID.Inspector.saveButton]
    }

    var cancelButton: XCUIElement {
        app.buttons[AccessibilityID.Inspector.cancelButton]
    }

    // MARK: - Actions

    @discardableResult
    func enterTitle(_ text: String) -> Self {
        titleField.tap()
        titleField.typeText(text)
        return self
    }

    @discardableResult
    func replaceTitle(with text: String) -> Self {
        titleField.tap()
        titleField.clearAndTypeText(text)
        return self
    }

    /// Save changes and return to the timeline.
    @discardableResult
    func tapSave() -> TimelineScreen {
        saveButton.tap()
        let screen = TimelineScreen(app: app)
        screen.waitForExistence()
        return screen
    }

    /// Discard changes and return to the timeline.
    @discardableResult
    func tapCancel() -> TimelineScreen {
        cancelButton.tap()
        let screen = TimelineScreen(app: app)
        screen.waitForExistence()
        return screen
    }
}

// MARK: - XCUIElement helpers

private extension XCUIElement {
    func clearAndTypeText(_ text: String) {
        guard let currentValue = value as? String, !currentValue.isEmpty else {
            typeText(text)
            return
        }
        let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count)
        typeText(deleteString)
        typeText(text)
    }
}
