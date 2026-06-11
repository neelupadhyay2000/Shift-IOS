import Foundation

/// Human-friendly relative date label for an event ("Today", "In 3 days",
/// "2 days ago") — gives the roster and event hero instant temporal context,
/// surfacing "when" before any other detail.
enum EventCountdown {
    static func label(for date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        switch days {
        case 0: return String(localized: "Today")
        case 1: return String(localized: "Tomorrow")
        case -1: return String(localized: "Yesterday")
        case let d where d > 1: return String(localized: "In \(d) days")
        default: return String(localized: "\(-days) days ago")
        }
    }
}
