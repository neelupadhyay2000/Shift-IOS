import Foundation

// MARK: - CalendarDay date helpers
//
// vendor_busy_dates.busy_date and the search p_on_date are SQL `date` (no time).
// We move them over the wire as "yyyy-MM-dd" strings and build/parse them from
// the *current* calendar's y/m/d so the day matches what the user sees — never a
// UTC formatter on a local midnight (which can shift the day across a TZ).
nonisolated enum CalendarDay {
    /// Local calendar day → "yyyy-MM-dd".
    static func string(from date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// "yyyy-MM-dd" → a Date at local noon (DST-safe anchor for that day).
    static func date(from string: String) -> Date? {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var c = DateComponents()
        c.year = parts[0]; c.month = parts[1]; c.day = parts[2]; c.hour = 12
        return Calendar.current.date(from: c)
    }
}

// MARK: - CalendarDayDTO
//
// One row from the `get_my_calendar` RPC: a busy day for the calling vendor, with
// its source (`manual` toggled by the vendor, or `booked` from a claimed event)
// and the event title for booked days. A day can appear twice (manual + booked).
nonisolated struct CalendarDayDTO: Decodable, Equatable {
    let busyDate: String          // "yyyy-MM-dd"
    let kind: String              // CalendarDayKind raw value
    let eventTitle: String?

    enum CodingKeys: String, CodingKey {
        case busyDate = "busy_date"
        case kind
        case eventTitle = "event_title"
    }

    var date: Date? { CalendarDay.date(from: busyDate) }
    var isBooked: Bool { kind == CalendarDayKind.booked.rawValue }
}

/// Source of a busy day.
nonisolated enum CalendarDayKind: String {
    case manual
    case booked
}

// MARK: - BusyDateUpsertDTO
//
// Upsert payload for toggling a manual busy day ON: writes the row keyed by
// (profile_id, busy_date) and explicitly clears deleted_at, so re-marking a day
// the vendor previously cleared resurrects the same unique slot. Toggling OFF is a
// separate soft-delete UPDATE in the service (sets deleted_at), not this payload.
nonisolated struct BusyDateUpsertDTO: Encodable, Equatable {
    let profileID: UUID
    let busyDate: String          // "yyyy-MM-dd"
    let note: String?

    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case busyDate = "busy_date"
        case note
        case deletedAt = "deleted_at"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(profileID, forKey: .profileID)
        try container.encode(busyDate, forKey: .busyDate)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encodeNil(forKey: .deletedAt)   // resurrect on re-mark
    }
}

// MARK: - get_my_calendar params

nonisolated struct GetMyCalendarParams: Encodable, Equatable, Sendable {
    let pFrom: String             // "yyyy-MM-dd"
    let pTo: String

    enum CodingKeys: String, CodingKey {
        case pFrom = "p_from"
        case pTo = "p_to"
    }
}
