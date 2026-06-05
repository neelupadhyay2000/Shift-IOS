import Foundation
import Models

// Pure (no network/disk) bidirectional mapping between `EventModel` and
// `EventDTO`. Marked `@MainActor` because SwiftData models are main-actor data;
// the mapping itself is a deterministic field-for-field transformation.

@MainActor
extension EventModel {
    /// Projects this event to its wire form.
    ///
    /// `ownerID` is supplied by the caller (the signed-in profile) because the
    /// local model has no owner column — it is implied by the device's user.
    func toDTO(ownerID: UUID) -> EventDTO {
        EventDTO(
            id: id,
            ownerID: ownerID,
            title: title,
            date: PostgresTimestamp(date),
            latitude: latitude,
            longitude: longitude,
            venueNames: venueNames,
            sunsetTime: PostgresTimestamp(sunsetTime),
            goldenHourStart: PostgresTimestamp(goldenHourStart),
            weatherSnapshot: weatherSnapshot.flatMap {
                try? JSONDecoder().decode(WeatherSnapshot.self, from: $0)
            },
            status: status.rawValue,
            wentLiveAt: PostgresTimestamp(wentLiveAt),
            completedAt: PostgresTimestamp(completedAt),
            // No local column; Supabase owns the shift "tickle".
            lastShiftedAt: nil,
            postEventReport: postEventReport,
            // Sync metadata is server-managed; omit on write.
            createdAt: nil,
            updatedAt: nil,
            deletedAt: nil
        )
    }
}

@MainActor
extension EventDTO {
    /// Builds a fresh `EventModel` carrying this row's scalar fields.
    /// Relationships are wired separately (events are graph roots and have none).
    func makeModel() -> EventModel {
        let model = EventModel(
            title: title,
            date: date.value,
            latitude: latitude ?? 0,
            longitude: longitude ?? 0
        )
        apply(to: model)
        return model
    }

    /// Overwrites `model`'s scalar fields from this row (upsert by id).
    /// `ownerID`, `lastShiftedAt`, and sync metadata have no local column and
    /// are intentionally not applied.
    func apply(to model: EventModel) {
        model.id = id
        model.title = title
        model.date = date.value
        model.latitude = latitude ?? 0
        model.longitude = longitude ?? 0
        model.venueNames = venueNames
        model.sunsetTime = sunsetTime?.value
        model.goldenHourStart = goldenHourStart?.value
        model.weatherSnapshot = weatherSnapshot.flatMap { try? JSONEncoder().encode($0) }
        model.status = EventStatus(rawValue: status) ?? .planning
        model.wentLiveAt = wentLiveAt?.value
        model.completedAt = completedAt?.value
        model.postEventReport = postEventReport
        // Server time of this version — the LWW basis (SHIFT-605).
        model.updatedAt = updatedAt?.value
    }
}
