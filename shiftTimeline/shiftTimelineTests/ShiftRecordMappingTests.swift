import Foundation
import Models
import Services
@testable import shiftTimeline
import SwiftData
import Testing

@Suite("ShiftRecord ↔ ShiftRecordDTO mapping")
@MainActor
struct ShiftRecordMappingTests {

    @Test("round-trip: scalars, event_id and source_block_id by relationship")
    func roundTrip() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let event = EventModel(title: "E", date: fixedTimestamp, latitude: 0, longitude: 0)
        let track = TimelineTrack(name: "Main", sortOrder: 0)
        let block = TimeBlockModel(title: "B", scheduledStart: fixedTimestamp, duration: 60)
        let record = ShiftRecord(timestamp: fixedTimestamp, deltaMinutes: -15, triggeredBy: .watch)
        context.insert(event)
        context.insert(track)
        context.insert(block)
        context.insert(record)
        track.event = event
        block.track = track
        record.event = event
        record.sourceBlock = block

        let dto = try record.toDTO()
        #expect(dto.id == record.id)
        #expect(dto.eventID == event.id)
        #expect(dto.sourceBlockID == block.id)
        #expect(dto.timestamp.value == fixedTimestamp)
        #expect(dto.deltaMinutes == -15)
        #expect(dto.triggeredBy == "watch")

        let model = dto.makeModel()
        #expect(model.id == record.id)
        #expect(model.timestamp == fixedTimestamp)
        #expect(model.deltaMinutes == -15)
        #expect(model.triggeredBy == .watch)
    }

    @Test("forward: a global shift has a nil source_block_id")
    func globalShift() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let event = EventModel(title: "E", date: fixedTimestamp, latitude: 0, longitude: 0)
        let record = ShiftRecord(timestamp: fixedTimestamp, deltaMinutes: 5, triggeredBy: .manual)
        context.insert(event)
        context.insert(record)
        record.event = event

        let dto = try record.toDTO()
        #expect(dto.sourceBlockID == nil)
    }

    @Test("forward: throws when the record is detached from its event")
    func detachedThrows() throws {
        let record = ShiftRecord(deltaMinutes: 1, triggeredBy: .manual)
        #expect(throws: ModelMappingError.missingEvent) {
            _ = try record.toDTO()
        }
    }
}
