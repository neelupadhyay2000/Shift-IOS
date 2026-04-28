import XCTest

/// Page object for `LiveDashboardView`.
///
/// `rootElement` anchors on the exit-live-mode button in the top-left toolbar,
/// which is present for the entire lifetime of the live dashboard screen.
@MainActor
final class LiveDashboardScreen: BaseScreen {

    override var rootElement: XCUIElement {
        app.buttons[AccessibilityID.Live.exitLiveButton]
    }

    // MARK: - Elements

    var exitLiveButton: XCUIElement {
        app.buttons[AccessibilityID.Live.exitLiveButton]
    }

    var shiftTimelineButton: XCUIElement {
        app.buttons[AccessibilityID.Live.shiftTimelineButton]
    }

    var activeBlockHero: XCUIElement {
        app.otherElements[AccessibilityID.Live.activeBlockHero]
    }

    var slideToAdvance: XCUIElement {
        app.otherElements[AccessibilityID.Live.slideToAdvance]
    }

    // MARK: - Actions

    /// Opens the Quick Shift sheet.
    @discardableResult
    func tapShiftTimeline() -> ShiftMenuScreen {
        shiftTimelineButton.tap()
        let screen = ShiftMenuScreen(app: app)
        screen.waitForExistence()
        return screen
    }

    /// Taps the Back button — presents the exit-confirmation dialog.
    /// Returns `self` because the dashboard is still on screen while
    /// the confirmation dialog is showing.
    @discardableResult
    func tapExit() -> Self {
        exitLiveButton.tap()
        return self
    }

    /// Confirms exit from the confirmation dialog.
    @discardableResult
    func confirmExit() -> Self {
        app.buttons["Exit Live Mode"].tap()
        return self
    }
}
