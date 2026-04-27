import Foundation

/// Launch argument flags injected by the test runner and read by the host app at startup.
///
/// The app checks `CommandLine.arguments` for these flags and adjusts behaviour:
/// in-memory store, data reset, fixture seeding, and clock override.
enum LaunchArgument {
    /// Boots the app with an in-memory `ModelContainer` and no CloudKit connectivity.
    /// Pass `"1"` to enable.
    static let uiTestMode = "-UITestMode"

    /// Wipes UserDefaults and the in-memory store before the first scene is served.
    /// Pass `"1"` to enable.
    static let resetData = "-ResetData"

    /// Name of a `TestFixture` case to seed into the in-memory store at boot.
    /// Pass the raw fixture name, e.g. `"singleEventFiveBlocks"`. (SHIFT-1002)
    static let seedFixture = "-SeedFixture"

    /// ISO 8601 timestamp that overrides "now" for the app's controlled clock.
    /// Pass an RFC 3339 string, e.g. `"2026-06-15T14:00:00Z"`. (SHIFT-1002)
    static let frozenNow = "-FrozenNow"
}
