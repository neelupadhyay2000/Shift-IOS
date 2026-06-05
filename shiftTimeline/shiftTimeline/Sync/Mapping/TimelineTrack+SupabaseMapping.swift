import Foundation
import Models

@MainActor
extension TimelineTrack {
    /// Projects this track to its wire form, reading `event_id` from the graph.
    /// - Throws: `ModelMappingError.missingEvent` if the track is detached.
    func toDTO() throws -> TrackDTO {
        guard let eventID = event?.id else { throw ModelMappingError.missingEvent }
        return toDTO(eventID: eventID)
    }

    /// Projects this track using an explicitly supplied `event_id` — used by the
    /// remote repository, which already knows the owning event.
    func toDTO(eventID: UUID) -> TrackDTO {
        TrackDTO(
            id: id,
            eventID: eventID,
            name: name,
            sortOrder: sortOrder,
            isDefault: isDefault,
            createdAt: nil,
            updatedAt: nil,
            deletedAt: nil
        )
    }
}

@MainActor
extension TrackDTO {
    /// Builds a fresh `TimelineTrack` with this row's scalar fields (relationship unwired).
    func makeModel() -> TimelineTrack {
        let model = TimelineTrack(name: name, sortOrder: sortOrder)
        apply(to: model)
        return model
    }

    /// Overwrites `model`'s scalar fields from this row (upsert by id).
    func apply(to model: TimelineTrack) {
        model.id = id
        model.name = name
        model.sortOrder = sortOrder
        model.isDefault = isDefault
    }

    /// Wires the parent relationship by resolving `event_id` against `events`.
    func linkRelationships(_ model: TimelineTrack, events: [UUID: EventModel]) {
        model.event = events[eventID]
    }
}
