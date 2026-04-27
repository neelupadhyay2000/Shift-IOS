import XCTest

/// Abstract base class for all SHIFT UI tests.
///
/// Every subclass automatically gets:
/// - A fresh `XCUIApplication` launched with `-UITestMode 1 -ResetData 1`
///   so tests run against an in-memory store with no CloudKit traffic.
/// - `continueAfterFailure = false` so the test stops on the first failure.
/// - Convenience assertion helpers that embed file/line info for clear failure messages.
///
/// Subclasses must NOT call `app.launch()` themselves; it is called here in
/// `setUpWithError()`. To inject additional launch arguments (e.g. fixture seeds),
/// override `configureLaunch()` and call `super.configureLaunch()` first.
@MainActor
class SHIFTUITestCase: XCTestCase {

    // MARK: - Properties

    /// The application under test. Recreated and relaunched before every test method.
    private(set) var app = XCUIApplication()

    // MARK: - Lifecycle

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication()
        configureLaunch()
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
        try super.tearDownWithError()
    }

    // MARK: - Launch configuration hook

    /// Applies the standard launch arguments. Subclasses may override to append
    /// additional arguments (e.g. fixture seeds) after calling `super`.
    func configureLaunch() {
        app.launchArguments = [
            LaunchArgument.uiTestMode, "1",
            LaunchArgument.resetData, "1",
        ]
    }

    // MARK: - Assertion helpers

    /// Waits up to `timeout` seconds for `element` to exist, then fails the test if it doesn't.
    func waitForExistence(
        _ element: XCUIElement,
        timeout: TimeInterval = 5,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            element.waitForExistence(timeout: timeout),
            "Element \(element.description) did not appear within \(timeout)s",
            file: file,
            line: line
        )
    }

    /// Asserts that `element` is currently hittable (visible and interactable).
    func assertHittable(
        _ element: XCUIElement,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            element.isHittable,
            "Expected \(element.description) to be hittable",
            file: file,
            line: line
        )
    }

    /// Taps `element` after waiting for it to exist. Fails if the element never appears.
    func tapWhenReady(
        _ element: XCUIElement,
        timeout: TimeInterval = 5,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        waitForExistence(element, timeout: timeout, file: file, line: line)
        element.tap()
    }
}
