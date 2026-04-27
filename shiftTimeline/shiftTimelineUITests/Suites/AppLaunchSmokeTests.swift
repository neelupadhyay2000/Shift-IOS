import XCTest

/// Smoke test that validates the app boots cleanly under UI test conditions and
/// presents the Event Roster within an acceptable time budget.
///
/// This is the canary test for SHIFT-1001: if it goes red, the test infrastructure
/// itself is broken and no other UI test result can be trusted.
final class AppLaunchSmokeTests: SHIFTUITestCase {

    /// Asserts the Event Roster screen is visible within 5 seconds of launch.
    ///
    /// Two elements confirm the roster is on screen:
    /// - The "Events" navigation bar title (set by `EventRosterView.navigationTitle`).
    /// - The "Add Event" toolbar button (`.accessibilityLabel("Add Event")`).
    ///
    /// The in-memory store is empty so the view renders `ContentUnavailableView`
    /// ("No events yet"), but both anchors above are always present regardless of
    /// store content.
    func testAppLaunches() {
        waitForExistence(app.navigationBars["Events"], timeout: 5)
        waitForExistence(app.buttons["Add Event"], timeout: 5)
    }
}
