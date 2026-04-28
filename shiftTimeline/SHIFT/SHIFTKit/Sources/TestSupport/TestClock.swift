import Foundation

/// A controlled clock for test fixtures and deterministic UI-test seeding.
///
/// **Rule:** every fixture builder must derive all `Date` values from
/// `clock.now`. Direct calls to `Date()` or `Date.now` inside a builder
/// are forbidden — they make fixtures non-deterministic across runs.
///
/// ### In unit tests
/// ```swift
/// let clock = TestClock(now: TestClock.reference.now)
/// try fixture.build(into: context, clock: clock)
/// ```
///
/// ### In the host app (UI-test fixture seeding, subtask 3)
/// ```swift
/// let clock = TestClock.fromLaunchArguments  // reads -FrozenNow <iso8601>
/// ```
public struct TestClock: Sendable {

    // MARK: - Properties

    /// The frozen "current" instant for this clock.
    public let now: Date

    // MARK: - Init

    /// Creates a clock frozen at the given date.
    public init(now: Date) {
        self.now = now
    }

    // MARK: - Factory

    /// Creates a clock by reading `-FrozenNow <iso8601>` from
    /// `CommandLine.arguments`. Falls back to the real wall clock
    /// when the flag is absent or the ISO 8601 string is malformed.
    public static var fromLaunchArguments: TestClock {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: "-FrozenNow"),
              args.indices.contains(idx + 1) else {
            return TestClock(now: Date())
        }
        let parsed = ISO8601DateFormatter().date(from: args[idx + 1])
        return TestClock(now: parsed ?? Date())
    }

    /// A stable reference timestamp used in unit tests: **2025-06-15 12:00:00 UTC**.
    ///
    /// All fixture builders pin their relative offsets to this point so
    /// tests produce identical data on every machine and CI run.
    public static let reference: TestClock = {
        // Force-unwrap is intentional: the literal is a compile-time constant
        // that will never fail to parse.
        let date = ISO8601DateFormatter().date(from: "2025-06-15T12:00:00Z")!
        return TestClock(now: date)
    }()
}
