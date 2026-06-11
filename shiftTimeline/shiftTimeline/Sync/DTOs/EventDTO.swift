import Foundation
import Models

/// Row in the Supabase `events` table.
///
/// Mirrors `EventModel`, plus the network-only columns Supabase owns:
/// `owner_id` (replaces CloudKit `ownerRecordName`) and the sync metadata
/// (`created_at` / `updated_at` / `deleted_at`).
///
/// `status` is coded as plain text — the column is free-text `text`, so the
/// DTO stays faithful to whatever Postgres holds; conversion to the typed
/// `EventStatus` (with a fallback for unknown values) happens in the mapping
/// layer.
///
/// Optional fields encode with `encodeIfPresent` (synthesized), so a `nil`
/// is **omitted** rather than sent as `null`. That keeps server-managed
/// columns (`created_at` / `updated_at`) on their defaults and avoids
/// clobbering existing Postgres values on upsert.
nonisolated struct EventDTO: Codable, Equatable {
    let id: UUID
    let ownerID: UUID
    let title: String
    let date: PostgresTimestamp
    let latitude: Double?
    let longitude: Double?
    let venueNames: [String]
    let sunsetTime: PostgresTimestamp?
    let goldenHourStart: PostgresTimestamp?
    let weatherSnapshot: WeatherSnapshot?
    let status: String
    let wentLiveAt: PostgresTimestamp?
    let completedAt: PostgresTimestamp?
    let lastShiftedAt: PostgresTimestamp?
    let postEventReport: PostEventReport?
    let createdAt: PostgresTimestamp?
    let updatedAt: PostgresTimestamp?
    let deletedAt: PostgresTimestamp?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case title
        case date
        case latitude
        case longitude
        case venueNames = "venue_names"
        case sunsetTime = "sunset_time"
        case goldenHourStart = "golden_hour_start"
        case weatherSnapshot = "weather_snapshot"
        case status
        case wentLiveAt = "went_live_at"
        case completedAt = "completed_at"
        case lastShiftedAt = "last_shifted_at"
        case postEventReport = "post_event_report"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(
        id: UUID,
        ownerID: UUID,
        title: String,
        date: PostgresTimestamp,
        latitude: Double? = nil,
        longitude: Double? = nil,
        venueNames: [String] = [],
        sunsetTime: PostgresTimestamp? = nil,
        goldenHourStart: PostgresTimestamp? = nil,
        weatherSnapshot: WeatherSnapshot? = nil,
        status: String,
        wentLiveAt: PostgresTimestamp? = nil,
        completedAt: PostgresTimestamp? = nil,
        lastShiftedAt: PostgresTimestamp? = nil,
        postEventReport: PostEventReport? = nil,
        createdAt: PostgresTimestamp? = nil,
        updatedAt: PostgresTimestamp? = nil,
        deletedAt: PostgresTimestamp? = nil
    ) {
        self.id = id
        self.ownerID = ownerID
        self.title = title
        self.date = date
        self.latitude = latitude
        self.longitude = longitude
        self.venueNames = venueNames
        self.sunsetTime = sunsetTime
        self.goldenHourStart = goldenHourStart
        self.weatherSnapshot = weatherSnapshot
        self.status = status
        self.wentLiveAt = wentLiveAt
        self.completedAt = completedAt
        self.lastShiftedAt = lastShiftedAt
        self.postEventReport = postEventReport
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
