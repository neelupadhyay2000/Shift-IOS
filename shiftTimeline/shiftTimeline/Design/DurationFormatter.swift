import Foundation

/// Minute-or-hour duration formatting helpers shared across UI surfaces.
///
/// Below 60 minutes a value is rendered as `"15 min"` / `"15m"` — preserving
/// the existing terse style used by row cards, shift banners, and previews.
/// At or above 60 minutes the value rolls up to hours with a remainder, so
/// `90 min` becomes `1h 30m` instead of the misleading `90 min`.
enum DurationFormatter {

    /// Compact spoken/visible form. Negative values are signed.
    /// Examples: `-30 min`, `45 min`, `1h`, `1h 30m`, `2h 5m`.
    static func compact(minutes: Int, signed: Bool = false) -> String {
        let absoluteMinutes = abs(minutes)
        let signPrefix: String = {
            guard signed else { return "" }
            if minutes > 0 { return "+" }
            if minutes < 0 { return "-" }
            return ""
        }()

        if absoluteMinutes < 60 {
            return "\(signPrefix)\(absoluteMinutes) min"
        }
        let hours = absoluteMinutes / 60
        let remainder = absoluteMinutes % 60
        if remainder == 0 {
            return "\(signPrefix)\(hours)h"
        }
        return "\(signPrefix)\(hours)h \(remainder)m"
    }

    /// Compact form keyed off a `TimeInterval` in seconds.
    static func compact(seconds: TimeInterval, signed: Bool = false) -> String {
        compact(minutes: Int(seconds / 60), signed: signed)
    }
}
