import Foundation
import Models
@testable import shiftTimeline
import Testing

@Suite("EventDTO — coding")
struct EventDTOTests {

    private func makeFull(
        id: UUID = UUID(),
        ownerID: UUID = UUID()
    ) -> EventDTO {
        EventDTO(
            id: id,
            ownerID: ownerID,
            title: "Summer Wedding",
            date: fixedPGTimestamp,
            latitude: 37.7749,
            longitude: -122.4194,
            venueNames: ["St. Mary's", "The Grand Hall"],
            sunsetTime: fixedPGTimestamp,
            goldenHourStart: fixedPGTimestamp,
            weatherSnapshot: WeatherSnapshot(
                entries: [BlockRainEntry(blockId: UUID(), rainProbability: 0.4)],
                fetchedAt: fixedTimestamp
            ),
            status: "live",
            wentLiveAt: fixedPGTimestamp,
            completedAt: nil,
            lastShiftedAt: fixedPGTimestamp,
            postEventReport: PostEventReport(
                entries: [],
                totalDriftMinutes: 12,
                totalShiftCount: 3,
                generatedAt: fixedTimestamp
            ),
            createdAt: fixedPGTimestamp,
            updatedAt: fixedPGTimestamp,
            deletedAt: nil
        )
    }

    // MARK: Encoding

    @Test("encodes every column key in snake_case")
    func encodesSnakeCaseKeys() throws {
        let json = try jsonObject(from: makeFull())
        #expect(json["owner_id"] != nil)
        #expect(json["venue_names"] != nil)
        #expect(json["sunset_time"] != nil)
        #expect(json["golden_hour_start"] != nil)
        #expect(json["weather_snapshot"] != nil)
        #expect(json["went_live_at"] != nil)
        #expect(json["last_shifted_at"] != nil)
        #expect(json["post_event_report"] != nil)
        #expect(json["created_at"] != nil)
        #expect(json["updated_at"] != nil)
        // No camelCase leakage.
        #expect(json["ownerId"] == nil)
        #expect(json["ownerID"] == nil)
        #expect(json["venueNames"] == nil)
    }

    @Test("encodes UUIDs as strings")
    func encodesUUIDAsString() throws {
        let id = UUID()
        let ownerID = UUID()
        let json = try jsonObject(from: makeFull(id: id, ownerID: ownerID))
        #expect((json["id"] as? String)?.lowercased() == id.uuidString.lowercased())
        #expect((json["owner_id"] as? String)?.lowercased() == ownerID.uuidString.lowercased())
    }

    @Test("encodes timestamptz columns as ISO 8601 strings")
    func encodesDateAsISOString() throws {
        let json = try jsonObject(from: makeFull())
        let date = try #require(json["date"] as? String)
        #expect(date == "2026-05-28T20:26:40.000Z")
        #expect(json["sunset_time"] as? String != nil)
    }

    @Test("encodes status as the raw text value")
    func encodesStatusAsText() throws {
        let json = try jsonObject(from: makeFull())
        #expect(json["status"] as? String == "live")
    }

    @Test("encodes venue_names as a JSON array")
    func encodesVenueNamesArray() throws {
        let json = try jsonObject(from: makeFull())
        #expect(json["venue_names"] as? [String] == ["St. Mary's", "The Grand Hall"])
    }

    @Test("encodes weather_snapshot as a nested JSON object, not a string blob")
    func encodesWeatherSnapshotAsObject() throws {
        let json = try jsonObject(from: makeFull())
        #expect((json["weather_snapshot"] as? [String: Any]) != nil)
    }

    @Test("omits nil optional columns so they are not written as null")
    func omitsNilColumns() throws {
        let dto = EventDTO(
            id: UUID(),
            ownerID: UUID(),
            title: "Minimal",
            date: fixedPGTimestamp,
            status: "planning"
        )
        let json = try jsonObject(from: dto)
        #expect(json["latitude"] == nil)
        #expect(json["longitude"] == nil)
        #expect(json["sunset_time"] == nil)
        #expect(json["weather_snapshot"] == nil)
        #expect(json["completed_at"] == nil)
        #expect(json["post_event_report"] == nil)
        #expect(json["created_at"] == nil)
        #expect(json["updated_at"] == nil)
        #expect(json["deleted_at"] == nil)
        // Required columns are always present.
        #expect(json["id"] != nil)
        #expect(json["owner_id"] != nil)
        #expect(json["title"] != nil)
        #expect(json["date"] != nil)
        #expect(json["status"] != nil)
        #expect(json["venue_names"] != nil)
    }

    // MARK: Decoding

    @Test("decodes a Postgres-style snake_case row")
    func decodesPostgresRow() throws {
        let id = UUID()
        let ownerID = UUID()
        let json = """
        {
            "id": "\(id.uuidString)",
            "owner_id": "\(ownerID.uuidString)",
            "title": "Gala",
            "date": "2026-06-04T17:00:00+00:00",
            "latitude": 51.5,
            "longitude": -0.12,
            "venue_names": ["Hall A"],
            "status": "completed",
            "went_live_at": "2026-06-04T18:00:00.500Z",
            "completed_at": null,
            "created_at": "2026-06-04T16:00:00.123456+00:00",
            "updated_at": "2026-06-04T16:30:00Z"
        }
        """
        let dto = try decodeDTO(EventDTO.self, from: json)
        #expect(dto.id == id)
        #expect(dto.ownerID == ownerID)
        #expect(dto.title == "Gala")
        #expect(dto.status == "completed")
        #expect(dto.latitude == 51.5)
        #expect(dto.venueNames == ["Hall A"])
        #expect(dto.date.value == SupabaseTimestamp.date(from: "2026-06-04T17:00:00Z"))
        #expect(dto.wentLiveAt?.value == SupabaseTimestamp.date(from: "2026-06-04T18:00:00.500Z"))
        // Explicit null and absent keys both decode to nil.
        #expect(dto.completedAt == nil)
        #expect(dto.sunsetTime == nil)
        #expect(dto.weatherSnapshot == nil)
    }

    // MARK: Round-trip

    @Test("round-trips a fully populated DTO to an equal value")
    func roundTripsFull() throws {
        let dto = makeFull()
        #expect(try roundTrip(dto) == dto)
    }

    @Test("round-trips a minimal DTO to an equal value")
    func roundTripsMinimal() throws {
        let dto = EventDTO(
            id: UUID(),
            ownerID: UUID(),
            title: "Minimal",
            date: fixedPGTimestamp,
            status: "planning"
        )
        #expect(try roundTrip(dto) == dto)
    }
}
