import Foundation
import Models
import Services
@testable import shiftTimeline
import SwiftData
import Testing

@Suite("TimelineTrack ↔ TrackDTO mapping")
@MainActor
struct TrackMappingTests {

    @Test("round-trip: scalars and event_id by relationship")
    func roundTrip() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let event = EventModel(title: "E", date: fixedTimestamp, latitude: 0, longitude: 0)
        let track = TimelineTrack(name: "Photography", sortOrder: 3, isDefault: true)
        context.insert(event)
        context.insert(track)
        track.event = event

        let dto = try track.toDTO()
        #expect(dto.id == track.id)
        #expect(dto.eventID == event.id)
        #expect(dto.name == "Photography")
        #expect(dto.sortOrder == 3)
        #expect(dto.isDefault == true)

        let model = dto.makeModel()
        #expect(model.id == track.id)
        #expect(model.name == "Photography")
        #expect(model.sortOrder == 3)
        #expect(model.isDefault == true)
    }

    @Test("forward: throws when the track is detached from its event")
    func detachedThrows() throws {
        let track = TimelineTrack(name: "Orphan", sortOrder: 0)
        #expect(throws: ModelMappingError.missingEvent) {
            _ = try track.toDTO()
        }
    }

    @Test("wiring: linkRelationships resolves event_id against the lookup")
    func wiring() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let event = EventModel(title: "E", date: fixedTimestamp, latitude: 0, longitude: 0)
        let track = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true)
        context.insert(event)
        context.insert(track)
        track.event = event

        let dto = try track.toDTO()
        let rebuilt = dto.makeModel()
        let rebuiltEvent = event.toDTO(ownerID: UUID()).makeModel()
        let secondContainer = try PersistenceController.forTesting()
        let secondContext = secondContainer.mainContext
        secondContext.insert(rebuiltEvent)
        secondContext.insert(rebuilt)

        dto.linkRelationships(rebuilt, events: [rebuiltEvent.id: rebuiltEvent])
        #expect(rebuilt.event?.id == event.id)
    }
}
