import Foundation
@testable import shiftTimeline
import Testing

@Suite("Availability — date helpers, params, DTOs")
struct AvailabilityServiceTests {

    // MARK: CalendarDay string/date helpers

    @Test("CalendarDay.string formats local y/m/d as yyyy-MM-dd")
    func calendarDayString() {
        var c = DateComponents(); c.year = 2026; c.month = 8; c.day = 5; c.hour = 12
        let date = Calendar.current.date(from: c)!
        #expect(CalendarDay.string(from: date) == "2026-08-05")
    }

    @Test("CalendarDay round-trips string → date → string")
    func calendarDayRoundTrip() {
        let parsed = CalendarDay.date(from: "2026-12-31")
        #expect(parsed != nil)
        #expect(CalendarDay.string(from: parsed!) == "2026-12-31")
    }

    @Test("CalendarDay.date rejects malformed input")
    func calendarDayRejectsBad() {
        #expect(CalendarDay.date(from: "not-a-date") == nil)
        #expect(CalendarDay.date(from: "2026-08") == nil)
    }

    // MARK: get_my_calendar params

    @Test("GetMyCalendarParams encodes p_from / p_to")
    func calendarParamsEncoding() throws {
        let params = GetMyCalendarParams(pFrom: "2026-08-01", pTo: "2026-08-31")
        let json = try jsonObject(from: params)
        #expect(json["p_from"] as? String == "2026-08-01")
        #expect(json["p_to"] as? String == "2026-08-31")
    }

    // MARK: busy-date upsert payload

    @Test("BusyDateUpsertDTO encodes profile/date and an explicit null deleted_at")
    func busyUpsertEncoding() throws {
        let uid = UUID()
        let payload = BusyDateUpsertDTO(profileID: uid, busyDate: "2026-08-20", note: nil)
        let json = try jsonObject(from: payload)
        #expect(json["profile_id"] as? String == uid.uuidString)
        #expect(json["busy_date"] as? String == "2026-08-20")
        #expect(json.keys.contains("deleted_at"))
        #expect(json["deleted_at"] is NSNull)   // resurrects a cleared day on re-mark
        #expect(json["note"] == nil)            // nil note omitted
    }

    // MARK: get_my_calendar row decoding

    @Test("CalendarDayDTO decodes manual and booked rows")
    func calendarDayDecoding() throws {
        let manual = try decodeDTO(CalendarDayDTO.self, from: """
        { "busy_date": "2026-08-20", "kind": "manual", "event_title": null }
        """)
        #expect(manual.kind == "manual")
        #expect(manual.isBooked == false)
        #expect(manual.eventTitle == nil)
        #expect(manual.date != nil)

        let booked = try decodeDTO(CalendarDayDTO.self, from: """
        { "busy_date": "2026-08-15", "kind": "booked", "event_title": "Summer Gala" }
        """)
        #expect(booked.isBooked)
        #expect(booked.eventTitle == "Summer Gala")
    }

    // MARK: search params carry the date filter

    @Test("searchParams maps onDate to p_on_date; nil omits it")
    func searchParamsOnDate() throws {
        var c = DateComponents(); c.year = 2026; c.month = 6; c.day = 20; c.hour = 12
        let date = Calendar.current.date(from: c)!
        let withDate = SupabaseMarketplaceService.searchParams(
            query: nil, category: nil, latitude: nil, longitude: nil,
            radiusKm: nil, limit: 20, offset: 0, onDate: date
        )
        #expect(withDate.pOnDate == "2026-06-20")
        let json = try jsonObject(from: withDate)
        #expect(json["p_on_date"] as? String == "2026-06-20")

        let noDate = SupabaseMarketplaceService.searchParams(
            query: nil, category: nil, latitude: nil, longitude: nil,
            radiusKm: nil, limit: 20, offset: 0, onDate: nil
        )
        #expect(noDate.pOnDate == nil)
        let json2 = try jsonObject(from: noDate)
        #expect(json2["p_on_date"] == nil)   // omitted → SQL default null → E10 behavior
    }
}
