import Foundation
import Testing
@testable import shiftTimeline

/// Verifies that `TimeRulerLayout.yOffset` produces correct Y positions for
/// golden-hour and sunset times, which are the values `SunsetMarkerView` uses
/// to place its amber and red marker lines on the ruler.
///
/// These tests satisfy the AC requirement for a "test to verify marker rendering
/// at known times" without needing a snapshot framework.
@Suite("SunsetMarkerView Layout")
struct SunsetMarkerViewTests {

    // MARK: - Helpers

    /// Builds a layout whose ruler spans `startHour` → `endHour` on today's date.
    private func makeLayout(
        startHour: Int,
        endHour: Int,
        pointsPerMinute: CGFloat = 4.0
    ) -> TimeRulerLayout {
        let calendar = Calendar.current
        let base = Date.now
        let start = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: base)!
        let end = calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: base)!
        return TimeRulerLayout(rulerStart: start, rulerEnd: end, pointsPerMinute: pointsPerMinute)
    }

    /// Returns a Date on today's date at the given hour and minute.
    private func time(hour: Int, minute: Int) -> Date {
        let calendar = Calendar.current
        var comps = calendar.dateComponents([.year, .month, .day], from: Date.now)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return calendar.date(from: comps)!
    }

    // MARK: - Y-offset correctness at known times

    @Test
    func goldenHourYOffsetMatchesExpectedPoints() {
        // Ruler: 8:00 AM → 10:00 PM, 4 pt/min
        // Golden hour: 7:17 PM = 677 min after ruler start
        let layout = makeLayout(startHour: 8, endHour: 22)
        let goldenHour = time(hour: 19, minute: 17)

        let y = layout.yOffset(for: goldenHour)

        #expect(y == CGFloat(677) * 4.0)
    }

    @Test
    func sunsetYOffsetMatchesExpectedPoints() {
        // Ruler: 8:00 AM → 10:00 PM, 4 pt/min
        // Sunset: 7:42 PM = 702 min after ruler start
        let layout = makeLayout(startHour: 8, endHour: 22)
        let sunset = time(hour: 19, minute: 42)

        let y = layout.yOffset(for: sunset)

        #expect(y == CGFloat(702) * 4.0)
    }

    @Test
    func goldenHourAlwaysRendersAboveSunset() {
        let layout = makeLayout(startHour: 8, endHour: 22)
        let goldenHour = time(hour: 19, minute: 17)
        let sunset = time(hour: 19, minute: 42)

        #expect(layout.yOffset(for: goldenHour) < layout.yOffset(for: sunset))
    }

    @Test
    func markerAtRulerStartProducesZeroOffset() {
        let start = time(hour: 9, minute: 0)
        let layout = TimeRulerLayout(
            rulerStart: start,
            rulerEnd: start.addingTimeInterval(3600),
            pointsPerMinute: 4.0
        )

        #expect(layout.yOffset(for: start) == 0.0)
    }

    @Test
    func markerAtRulerEndProducesTotalHeight() {
        let layout = makeLayout(startHour: 8, endHour: 22)

        let y = layout.yOffset(for: layout.rulerEnd)

        #expect(y == layout.totalHeight)
    }

    @Test
    func yOffsetScalesLinearlyWithPointsPerMinute() {
        let golden = time(hour: 19, minute: 0)

        let layout1 = TimeRulerLayout(
            rulerStart: time(hour: 8, minute: 0),
            rulerEnd: time(hour: 22, minute: 0),
            pointsPerMinute: 2.0
        )
        let layout2 = TimeRulerLayout(
            rulerStart: time(hour: 8, minute: 0),
            rulerEnd: time(hour: 22, minute: 0),
            pointsPerMinute: 4.0
        )

        #expect(layout2.yOffset(for: golden) == layout1.yOffset(for: golden) * 2)
    }
}
