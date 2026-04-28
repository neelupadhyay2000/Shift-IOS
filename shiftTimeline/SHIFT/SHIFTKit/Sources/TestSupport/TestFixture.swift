import Foundation

/// All available test fixture presets for the SHIFT test suite.
///
/// Each case corresponds to a self-contained SwiftData graph inserted by its
/// `FixtureBuilding` conformance. Builders are implemented in subtasks 2–4
/// alongside one unit test per fixture.
///
/// ### Fixture naming convention
/// The launch-argument token is returned by `serialisedName`.
/// Parameterised cases encode their associated value after an underscore:
/// - `"eventWithVendors_3"` → `.eventWithVendors(count: 3)`
/// - `"liveEventInProgress_0"` → `.liveEventInProgress(blockIndex: 0)`
///
/// ### Usage (unit tests, subtask 2+)
/// ```swift
/// let context = try PersistenceController.forTesting().mainContext
/// let clock = TestClock.reference
/// try TestFixture.singleEventFiveBlocks.build(into: context, clock: clock)
/// ```
///
/// ### Usage (host app, subtask 3)
/// ```swift
/// // shiftTimelineApp reads -SeedFixture <name> at boot and calls:
/// try TestFixture.named(name)?.build(into: context, clock: .fromLaunchArguments)
/// ```
public enum TestFixture: Hashable, Sendable {

    // MARK: - Cases

    /// One event with five sequential 30-minute blocks on the Main track.
    case singleEventFiveBlocks

    /// One event with a full classic-wedding timeline applied from the template library.
    case weddingTemplateApplied

    /// One event with three named tracks (Main, Ceremony, Reception) and
    /// blocks distributed across them.
    case multiTrackConference

    /// One event with `count` vendors attached (cycles through all `VendorRole` values).
    case eventWithVendors(count: Int)

    /// One event in live mode where the block at `blockIndex` (0-based) is `.active`.
    case liveEventInProgress(blockIndex: Int)

    /// One event with one block that has `isOutdoor = true` and a rain-forecast
    /// weather snapshot so `RainWarningBanner` renders in tests.
    case eventWithRainForecastedBlock

    /// One event that has `sunsetTime` and `goldenHourStart` populated so
    /// `SunsetMarkerView` and `SunsetBanner` render in tests.
    case eventWithSunsetBlocks

    // MARK: - Serialisation

    /// The token written after `-SeedFixture` in `XCUIApplication.launchArguments`.
    /// Parameterised cases encode their associated value as `"<caseName>_<value>"`.
    public var serialisedName: String {
        switch self {
        case .singleEventFiveBlocks:            return "singleEventFiveBlocks"
        case .weddingTemplateApplied:           return "weddingTemplateApplied"
        case .multiTrackConference:             return "multiTrackConference"
        case .eventWithVendors(let count):      return "eventWithVendors_\(count)"
        case .liveEventInProgress(let idx):     return "liveEventInProgress_\(idx)"
        case .eventWithRainForecastedBlock:     return "eventWithRainForecastedBlock"
        case .eventWithSunsetBlocks:            return "eventWithSunsetBlocks"
        }
    }

    /// Resolves a `-SeedFixture` token back to its `TestFixture` case.
    ///
    /// Returns `nil` for unknown tokens or parameterised tokens with a missing
    /// or negative integer suffix.
    public static func named(_ name: String) -> TestFixture? {
        switch name {
        case "singleEventFiveBlocks":            return .singleEventFiveBlocks
        case "weddingTemplateApplied":           return .weddingTemplateApplied
        case "multiTrackConference":             return .multiTrackConference
        case "eventWithRainForecastedBlock":     return .eventWithRainForecastedBlock
        case "eventWithSunsetBlocks":            return .eventWithSunsetBlocks
        default:
            break
        }

        let vendorPrefix = "eventWithVendors_"
        if name.hasPrefix(vendorPrefix),
           let count = Int(name.dropFirst(vendorPrefix.count)),
           count >= 0 {
            return .eventWithVendors(count: count)
        }

        let livePrefix = "liveEventInProgress_"
        if name.hasPrefix(livePrefix),
           let idx = Int(name.dropFirst(livePrefix.count)),
           idx >= 0 {
            return .liveEventInProgress(blockIndex: idx)
        }

        return nil
    }
}
