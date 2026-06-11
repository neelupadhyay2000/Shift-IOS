import Foundation
import Testing
@testable import shiftTimeline

/// Covers the pure fire-time decision for the day-before event briefing —
/// 6 PM local time the evening before the event's first block.
struct DayBeforeBriefingNotifierTests {

    private let calendar = Calendar.current

    /// A date at the given hour on a day `daysFromNow` days after `base`.
    private func date(daysAfter base: Date, days: Int, hour: Int) -> Date {
        let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: base)) ?? base
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
    }

    @Test func fireDateIsSixPMTheEveningBefore() {
        let now = date(daysAfter: .now, days: 0, hour: 9)
        let eventStart = date(daysAfter: now, days: 3, hour: 10)

        let fire = DayBeforeBriefingNotifier.fireDate(eventStart: eventStart, now: now, calendar: calendar)

        let expected = date(daysAfter: now, days: 2, hour: DayBeforeBriefingNotifier.fireHour)
        #expect(fire == expected)
    }

    @Test func fireDateNilWhenEveningBeforeAlreadyPassed() {
        // Event tomorrow morning, but it's already 9 PM tonight — the 6 PM
        // slot has passed, so nothing useful to schedule.
        let now = date(daysAfter: .now, days: 0, hour: 21)
        let eventStart = date(daysAfter: now, days: 1, hour: 10)

        #expect(DayBeforeBriefingNotifier.fireDate(eventStart: eventStart, now: now, calendar: calendar) == nil)
    }

    @Test func fireDateNilForPastEvent() {
        let now = date(daysAfter: .now, days: 0, hour: 12)
        let eventStart = date(daysAfter: now, days: -2, hour: 10)

        #expect(DayBeforeBriefingNotifier.fireDate(eventStart: eventStart, now: now, calendar: calendar) == nil)
    }

    @Test func fireDateStillScheduledWhenEventIsTomorrowAndItIsMorning() {
        // It's 8 AM; event is tomorrow — tonight's 6 PM briefing is still ahead.
        let now = date(daysAfter: .now, days: 0, hour: 8)
        let eventStart = date(daysAfter: now, days: 1, hour: 14)

        let fire = DayBeforeBriefingNotifier.fireDate(eventStart: eventStart, now: now, calendar: calendar)

        let expected = date(daysAfter: now, days: 0, hour: DayBeforeBriefingNotifier.fireHour)
        #expect(fire == expected)
    }

    @Test func identifierIsDeterministicPerEvent() {
        let id = UUID()
        #expect(
            DayBeforeBriefingNotifier.identifier(for: id) == DayBeforeBriefingNotifier.identifier(for: id)
        )
        #expect(DayBeforeBriefingNotifier.identifier(for: id).contains(id.uuidString))
    }

    @Test func bodyMentionsTitleAndFirstBlock() {
        let firstBlock = date(daysAfter: .now, days: 1, hour: 10)
        let body = DayBeforeBriefingNotifier.body(
            eventTitle: "Patel Wedding",
            firstBlockStart: firstBlock,
            sunsetTime: nil
        )

        #expect(body.contains("Patel Wedding"))
        #expect(body.contains(firstBlock.formatted(date: .omitted, time: .shortened)))
    }

    @Test func bodyIncludesSunsetWhenKnown() {
        let firstBlock = date(daysAfter: .now, days: 1, hour: 10)
        let sunset = date(daysAfter: .now, days: 1, hour: 19)
        let body = DayBeforeBriefingNotifier.body(
            eventTitle: "Patel Wedding",
            firstBlockStart: firstBlock,
            sunsetTime: sunset
        )

        #expect(body.contains(sunset.formatted(date: .omitted, time: .shortened)))
    }
}
