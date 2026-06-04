import Foundation
@testable import shiftTimeline
import Testing

// MARK: - SupabaseTimestamp

@Suite("SupabaseTimestamp — Postgres timestamptz coding")
struct SupabaseTimestampTests {

    /// 2026-06-04T17:00:00 UTC, built from components so the test owns the instant.
    private static var june4_17h: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 4
        components.hour = 17
        components.minute = 0
        components.second = 0
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar.date(from: components) ?? .distantPast
    }

    @Test("encodes a whole-second date as ISO 8601 UTC with millisecond precision")
    func encodesWholeSecond() {
        #expect(SupabaseTimestamp.string(from: Self.june4_17h) == "2026-06-04T17:00:00.000Z")
    }

    @Test("parses a plain UTC 'Z' timestamp")
    func parsesZuluNoFraction() {
        #expect(SupabaseTimestamp.date(from: "2026-06-04T17:00:00Z") == Self.june4_17h)
    }

    @Test("parses an explicit +00:00 offset identically to 'Z'")
    func parsesExplicitOffset() {
        #expect(SupabaseTimestamp.date(from: "2026-06-04T17:00:00+00:00") == Self.june4_17h)
    }

    @Test("parses millisecond fractional seconds")
    func parsesMilliseconds() {
        let parsed = SupabaseTimestamp.date(from: "2026-06-04T17:00:00.000Z")
        #expect(parsed == Self.june4_17h)
    }

    @Test("parses Postgres microsecond precision by truncating to milliseconds")
    func parsesMicroseconds() {
        // .123456 (6 digits) exceeds ISO8601DateFormatter's millisecond limit;
        // it must still parse, truncated to the .123 millisecond instant.
        let micro = SupabaseTimestamp.date(from: "2026-06-04T17:00:00.123456+00:00")
        let milli = SupabaseTimestamp.date(from: "2026-06-04T17:00:00.123Z")
        #expect(micro != nil)
        #expect(micro == milli)
    }

    @Test("parses microsecond precision with a non-UTC offset")
    func parsesMicrosecondsWithOffset() {
        let withOffset = SupabaseTimestamp.date(from: "2026-06-04T22:30:00.654321+05:30")
        let asUTC = SupabaseTimestamp.date(from: "2026-06-04T17:00:00.654Z")
        #expect(withOffset == asUTC)
    }

    @Test("returns nil for a non-timestamp string")
    func rejectsGarbage() {
        #expect(SupabaseTimestamp.date(from: "not-a-timestamp") == nil)
        #expect(SupabaseTimestamp.date(from: "") == nil)
    }

    @Test("round-trips a whole-second date through string and back")
    func roundTripsWholeSecond() {
        let encoded = SupabaseTimestamp.string(from: fixedTimestamp)
        #expect(SupabaseTimestamp.date(from: encoded) == fixedTimestamp)
    }
}

// MARK: - PostgresTimestamp

@Suite("PostgresTimestamp — Codable wrapper")
struct PostgresTimestampTests {

    /// Wraps the timestamp in an object so encode/decode never rely on
    /// top-level JSON fragment support (a value type only ever nested in a DTO).
    private struct Box: Codable, Equatable {
        let at: PostgresTimestamp
    }

    @Test("encodes as a JSON string, not a deferred-to-date number")
    func encodesAsString() throws {
        let json = try jsonObject(from: Box(at: fixedPGTimestamp))
        let at = try #require(json["at"] as? String)
        #expect(at == "2026-05-28T20:26:40.000Z")
    }

    @Test("decodes from a Postgres-style timestamptz string")
    func decodesFromString() throws {
        let decoded = try decodeDTO(Box.self, from: #"{ "at": "2026-06-04T17:00:00.123456+00:00" }"#)
        #expect(decoded.at.value == SupabaseTimestamp.date(from: "2026-06-04T17:00:00.123Z"))
    }

    @Test("throws on an invalid timestamp string")
    func throwsOnInvalid() {
        #expect(throws: DecodingError.self) {
            _ = try decodeDTO(Box.self, from: #"{ "at": "nonsense" }"#)
        }
    }

    @Test("round-trips a whole-second value to an equal wrapper")
    func roundTrips() throws {
        let box = Box(at: fixedPGTimestamp)
        #expect(try roundTrip(box) == box)
    }

    @Test("nullable initializer preserves nil")
    func nullableInit() {
        let none = PostgresTimestamp(Date?.none)
        #expect(none == nil)
        let some = PostgresTimestamp(Date?.some(fixedTimestamp))
        #expect(some == fixedPGTimestamp)
    }
}
