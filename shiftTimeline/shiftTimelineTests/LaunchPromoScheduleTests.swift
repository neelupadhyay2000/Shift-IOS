import Foundation
import Testing
@testable import shiftTimeline

/// Covers the once-per-calendar-day gate for the launch promo interstitial.
struct LaunchPromoScheduleTests {

    private let calendar = Calendar.current
    private let now = Date.now

    @Test func showsWhenNeverShown() {
        #expect(LaunchPromoSchedule.shouldShow(lastShown: nil, now: now))
    }

    @Test func doesNotShowTwiceOnTheSameDay() {
        let earlierToday = now.addingTimeInterval(-60)
        #expect(!LaunchPromoSchedule.shouldShow(lastShown: earlierToday, now: now))
    }

    @Test func doesNotShowImmediatelyAfterShowing() {
        #expect(!LaunchPromoSchedule.shouldShow(lastShown: now, now: now))
    }

    @Test func showsAgainTheNextDay() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        #expect(LaunchPromoSchedule.shouldShow(lastShown: yesterday, now: now))
    }

    @Test func showsWhenLastShownIsLongAgo() {
        let lastWeek = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        #expect(LaunchPromoSchedule.shouldShow(lastShown: lastWeek, now: now))
    }
}
