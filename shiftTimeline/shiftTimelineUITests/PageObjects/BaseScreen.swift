import XCTest

/// Concrete base class for all SHIFT page-object screens.
///
/// Stores `app` and enforces that subclasses declare their `rootElement`.
/// All `Screen` protocol requirements are satisfied by the `Screen` extension;
/// subclasses need only override `rootElement` and add their own element
/// accessors and action methods.
///
/// Example subclass:
/// ```swift
/// final class EventRosterScreen: BaseScreen {
///
///     override var rootElement: XCUIElement {
///         app.navigationBars[AccessibilityID.Roster.navigationBar]
///     }
///
///     var addEventButton: XCUIElement {
///         app.buttons[AccessibilityID.Roster.addEvent]
///     }
///
///     @discardableResult
///     func tapAddEvent() -> CreateEventScreen {
///         addEventButton.tap()
///         return CreateEventScreen(app: app)
///     }
/// }
/// ```
@MainActor
class BaseScreen: Screen {

    // MARK: - Screen

    let app: XCUIApplication

    /// Override in every subclass to return the element that uniquely
    /// identifies this screen (e.g. a navigation bar, a distinctive button).
    /// Calling `waitForExistence` or `assertVisible` on a `BaseScreen` instance
    /// directly (without overriding) will crash the test with a clear message.
    var rootElement: XCUIElement {
        fatalError(
            "\(type(of: self)) must override `rootElement` — " +
            "return the XCUIElement that proves this screen is on-screen."
        )
    }

    // MARK: - Init

    required init(app: XCUIApplication) {
        self.app = app
    }
}
