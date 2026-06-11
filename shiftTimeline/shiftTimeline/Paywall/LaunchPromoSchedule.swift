import Foundation

/// Once-per-calendar-day gate for the launch promo interstitial.
///
/// The last-shown moment persists in `UserDefaults`, so the promo appears at
/// most once a day across launches — not once per cold launch.
nonisolated enum LaunchPromoSchedule {

    static let defaultsKey = "launchPromoLastShownAt"

    /// True when the promo hasn't been shown yet today.
    static func shouldShow(lastShown: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        guard let lastShown else { return true }
        return !calendar.isDate(lastShown, inSameDayAs: now)
    }
}
