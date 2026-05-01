import Foundation
import Models
import Services
import SwiftData
import Testing

/// Verifies that `PersistenceController.recordShift` correctly creates and
/// links a `ShiftRecord` to its owning `EventModel`.
///
/// These tests guard against the regression where shift commits wrote block
/// mutations to SwiftData but never stamped a `ShiftRecord`, leaving
/// `event.shiftRecords` permanently empty and `PostEventReport.totalShiftCount`
/// always zero.
@Suite("ShiftRecord Stamping")
struct ShiftRecordStampingTests {

    // MARK: - Helpers

    @MainActor
    private func makeEvent(in context: ModelContext) -> EventModel {
        let event = EventModel(title: "Test Event", date: .now, latitude: 0, longitude: 0)
        context.insert(event)
        return event
    }

    @MainActor
    private func makeActiveBlock(in context: ModelContext, for event: EventModel) -> TimeBlockModel {
        let track = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true)
        track.event = event
        context.insert(track)
        let block = TimeBlockModel(
            title: "Ceremony",
            scheduledStart: .now,
            originalStart: .now,
            duration: 1800
        )
        block.status = .active
        block.track = track
        context.insert(block)
        return block
    }

    // MARK: - Tests

    @Test @MainActor
    func recordShiftCreatesLinkedShiftRecord() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let event = makeEvent(in: context)
        let block = makeActiveBlock(in: context, for: event)

        PersistenceController.recordShift(
            deltaMinutes: 10,
            triggeredBy: .manual,
            sourceBlock: block,
            event: event,
            into: context
        )
        try context.save()

        #expect((event.shiftRecords ?? []).count == 1)
        #expect(event.shiftRecords?.first?.deltaMinutes == 10)
        #expect(event.shiftRecords?.first?.triggeredBy == .manual)
    }

    @Test @MainActor
    func recordShiftWithWatchSourceStampsCorrectTrigger() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let event = makeEvent(in: context)

        PersistenceController.recordShift(
            deltaMinutes: 5,
            triggeredBy: .watch,
            sourceBlock: nil,
            event: event,
            into: context
        )
        try context.save()

        #expect(event.shiftRecords?.first?.triggeredBy == .watch)
    }

    @Test @MainActor
    func multipleShiftsAccumulateRecordsOnEvent() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let event = makeEvent(in: context)

        for delta in [5, 10, 15] {
            PersistenceController.recordShift(
                deltaMinutes: delta,
                triggeredBy: .manual,
                sourceBlock: nil,
                event: event,
                into: context
            )
        }
        try context.save()

        let records = event.shiftRecords ?? []
        #expect(records.count == 3)
        #expect(records.map(\.deltaMinutes).sorted() == [5, 10, 15])
    }

    @Test @MainActor
    func recordShiftWithNilSourceBlockIsPermitted() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let event = makeEvent(in: context)

        PersistenceController.recordShift(
            deltaMinutes: 3,
            triggeredBy: .manual,
            sourceBlock: nil,
            event: event,
            into: context
        )
        try context.save()

        #expect((event.shiftRecords ?? []).count == 1)
        #expect(event.shiftRecords?.first?.sourceBlock == nil)
    }
}
