import Foundation

// MARK: - Postgres timestamptz coding

/// Conversions between `Date` and the textual form Postgres uses for
/// `timestamptz` columns.
///
/// JSON has no native date type, so PostgREST serializes every `timestamptz`
/// as an ISO 8601 string with an explicit UTC offset and up to **microsecond**
/// fractional precision, e.g. `2026-06-04T17:00:00.123456+00:00`. Every sync
/// DTO codes its timestamp fields as `String` through these helpers (via the
/// ``PostgresTimestamp`` wrapper) rather than relying on a `JSONDecoder`
/// date strategy — so the wire format is identical whether a row is decoded by
/// the Supabase SDK's PostgREST coder or a plain `JSONDecoder` in a unit test.
nonisolated enum SupabaseTimestamp {

    /// Serializes a `Date` to an ISO 8601 UTC string with millisecond fractional
    /// precision — a form Postgres accepts for `timestamptz` columns.
    static func string(from date: Date) -> String {
        encodingFormatter.string(from: date)
    }

    /// Parses a Postgres `timestamptz` string into a `Date`, tolerating the
    /// presence or absence of fractional seconds and fractional precision
    /// beyond milliseconds (Postgres emits microseconds, which exceeds what
    /// `ISO8601DateFormatter` accepts directly).
    ///
    /// - Returns: The parsed `Date`, or `nil` if the string is not a
    ///   recognizable ISO 8601 timestamp.
    static func date(from string: String) -> Date? {
        if let date = fractionalFormatter.date(from: string) { return date }
        if let date = plainFormatter.date(from: string) { return date }
        // Postgres microsecond precision (>3 fractional digits) trips the
        // fractional formatter; truncate to milliseconds and retry.
        if let normalized = normalizedToMilliseconds(string),
           let date = fractionalFormatter.date(from: normalized) {
            return date
        }
        return nil
    }

    // MARK: Formatters

    // These `ISO8601DateFormatter`s are configured once and only ever read from
    // afterwards; Apple's date formatters are thread-safe for concurrent
    // `string(from:)` / `date(from:)`, so `nonisolated(unsafe)` is sound here
    // (matches `PostEventReportPDFGenerator`'s shared-formatter pattern).

    /// Emits `...HH:mm:ss.SSSZ` in UTC.
    private nonisolated(unsafe) static let encodingFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    /// Parses timestamps that carry fractional seconds (1–3 digits).
    private nonisolated(unsafe) static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Parses timestamps with no fractional seconds.
    private nonisolated(unsafe) static let plainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Truncates a fractional-seconds run longer than three digits down to
    /// milliseconds so `ISO8601DateFormatter` can parse Postgres microsecond
    /// timestamps. Returns `nil` when there is nothing to truncate.
    private static func normalizedToMilliseconds(_ string: String) -> String? {
        guard let dotIndex = string.firstIndex(of: ".") else { return nil }
        let firstFractionDigit = string.index(after: dotIndex)
        var cursor = firstFractionDigit
        while cursor < string.endIndex, string[cursor].isNumber {
            cursor = string.index(after: cursor)
        }
        let digitCount = string.distance(from: firstFractionDigit, to: cursor)
        guard digitCount > 3 else { return nil }
        let millisecondEnd = string.index(firstFractionDigit, offsetBy: 3)
        return String(string[string.startIndex..<millisecondEnd]) + String(string[cursor...])
    }
}

// MARK: - PostgresTimestamp

/// A `Date` that codes as a Postgres `timestamptz` string.
///
/// Wrapping timestamp fields in this type lets the DTOs use **synthesized**
/// `Codable` while keeping the wire format self-contained — the value always
/// round-trips through ``SupabaseTimestamp`` regardless of the coder in use.
/// Equality (and hashing) compare the underlying `Date` exactly; note that
/// encoding is millisecond-precision, so a value built from a sub-millisecond
/// `Date` will not byte-for-byte round-trip — construct test fixtures from
/// whole-second or millisecond `Date`s.
nonisolated struct PostgresTimestamp: Hashable, Codable {
    let value: Date

    init(_ value: Date) {
        self.value = value
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let date = SupabaseTimestamp.date(from: raw) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Not a valid Postgres timestamptz: \(raw)"
                )
            )
        }
        value = date
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(SupabaseTimestamp.string(from: value))
    }
}

extension PostgresTimestamp {
    /// Wraps a `Date?`, preserving `nil`.
    init?(_ value: Date?) {
        guard let value else { return nil }
        self.init(value)
    }
}
