import XCTest

/// Page object for `QuickShiftSheet`.
///
/// The sheet presents inside a `NavigationStack` with a static title
/// "Shift Timeline", making the nav bar the stable root element.
@MainActor
final class ShiftMenuScreen: BaseScreen {

    override var rootElement: XCUIElement {
        app.navigationBars["Shift Timeline"]
    }

    // MARK: - Elements

    var cancelButton: XCUIElement {
        app.buttons[AccessibilityID.Shift.cancelButton]
    }

    /// The displayed minute count in the custom entry row.
    var amountStepper: XCUIElement {
        app.staticTexts[AccessibilityID.Shift.amountStepper]
    }

    /// The apply-shift button rendered only when the custom entry row is open.
    var applyShiftButton: XCUIElement {
        app.buttons[AccessibilityID.Shift.applyShiftButton]
    }

    var customButton: XCUIElement {
        app.buttons["Custom"]
    }

    // MARK: - Queries

    /// Returns the preset button for the given minute value (+5, +10, +15).
    func presetButton(minutes: Int) -> XCUIElement {
        app.buttons["shift.preset_\(minutes)min"]
    }

    // MARK: - Actions

    /// Taps a preset shift button and returns to the live dashboard.
    @discardableResult
    func tapPreset(minutes: Int) -> LiveDashboardScreen {
        presetButton(minutes: minutes).tap()
        let screen = LiveDashboardScreen(app: app)
        screen.waitForExistence()
        return screen
    }

    /// Cancels and returns to the live dashboard.
    @discardableResult
    func tapCancel() -> LiveDashboardScreen {
        cancelButton.tap()
        let screen = LiveDashboardScreen(app: app)
        screen.waitForExistence()
        return screen
    }

    /// Expands the custom-entry row.
    @discardableResult
    func tapCustom() -> Self {
        customButton.tap()
        return self
    }

    /// Applies the custom shift amount and returns to the live dashboard.
    @discardableResult
    func tapApplyShift() -> LiveDashboardScreen {
        applyShiftButton.tap()
        let screen = LiveDashboardScreen(app: app)
        screen.waitForExistence()
        return screen
    }
}
