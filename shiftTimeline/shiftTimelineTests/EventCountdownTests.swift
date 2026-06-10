import Foundation
@testable import shiftTimeline
import Testing

@Suite("Event countdown label")
struct EventCountdownTests {

    private let cal = Calendar(identifier: .gregorian)

    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: hour)) ?? .distantPast
    }

    @Test("today, tomorrow, yesterday are named")
    func namedDays() {
        let now = day(2026, 6, 9)
        #expect(EventCountdown.label(for: day(2026, 6, 9), now: now, calendar: cal) == "Today")
        #expect(EventCountdown.label(for: day(2026, 6, 10), now: now, calendar: cal) == "Tomorrow")
        #expect(EventCountdown.label(for: day(2026, 6, 8), now: now, calendar: cal) == "Yesterday")
    }

    @Test("future and past spans count days")
    func spans() {
        let now = day(2026, 6, 9)
        #expect(EventCountdown.label(for: day(2026, 6, 12), now: now, calendar: cal) == "In 3 days")
        #expect(EventCountdown.label(for: day(2026, 6, 4), now: now, calendar: cal) == "5 days ago")
    }

    @Test("uses calendar-day boundaries, not 24h windows")
    func calendarDayBoundary() {
        // Late tonight → early tomorrow is "Tomorrow", not "Today".
        let now = day(2026, 6, 9, hour: 23)
        let earlyTomorrow = day(2026, 6, 10, hour: 1)
        #expect(EventCountdown.label(for: earlyTomorrow, now: now, calendar: cal) == "Tomorrow")
    }
}
