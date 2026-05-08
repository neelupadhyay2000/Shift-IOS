import Foundation

/// Minute-or-hour duration formatting helpers shared across UI surfaces.
enum DurationFormatter {

    /// Compact spoken/visible form. Negative values are signed..
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
