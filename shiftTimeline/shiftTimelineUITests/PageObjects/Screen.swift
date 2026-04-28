import XCTest

/// Contract every SHIFT page-object screen must satisfy.
///
/// The `rootElement` property is the single anchor that proves a screen is
/// on-screen. Default implementations of `waitForExistence(timeout:)` and
/// `assertVisible()` are provided via the protocol extension below, so
/// conforming types only need to supply `app` and `rootElement`.
///
/// Usage pattern:
/// ```swift
/// final class EventRosterScreen: BaseScreen {
///     override var rootElement: XCUIElement {
///         app.navigationBars[AccessibilityID.Roster.navigationBar]
///     }
/// }
///
/// // In a test:
/// let roster = EventRosterScreen(app: app)
/// roster.assertVisible()
/// ```
protocol Screen: AnyObject {
    /// The application under test.
    var app: XCUIApplication { get }

    /// The XCUIElement whose existence proves this screen is on-screen.
    /// Returned by `waitForExistence(timeout:)` and `assertVisible()`.
    var rootElement: XCUIElement { get }

    /// Waits up to `timeout` seconds for `rootElement` to exist, failing the
    /// test if it never appears.
    func waitForExistence(timeout: TimeInterval)

    /// Asserts `rootElement` currently exists without waiting.
    func assertVisible()
}

// MARK: - Default implementations

extension Screen {
    func waitForExistence(timeout: TimeInterval = 5) {
        XCTAssertTrue(
            rootElement.waitForExistence(timeout: timeout),
            "\(Self.self) — rootElement did not appear within \(timeout)s: \(rootElement)"
        )
    }

    func assertVisible() {
        XCTAssertTrue(
            rootElement.exists,
            "\(Self.self) — rootElement is not on screen: \(rootElement)"
        )
    }
}
