import Foundation
import Models
import Services
import SwiftData
import Testing

/// Covers the .planning → .live entry transition exercised by
/// `EventModel.applyGoLiveMutation()`.
///
/// Each test creates an isolated in-memory SwiftData container so
/// relationship graphs (tracks → blocks) are fully wired without
/// hitting a real CloudKit store.
@Suite("EventModel.applyGoLiveMutation")
struct EventGoLiveTransitionTests {

    // MARK: - Helpers

    @MainActor
    private func makeEvent(
        status: EventStatus = .planning,
        in context: ModelContext
    ) -> EventModel {
        let event = EventModel(title: "Test Wedding", date: .now, latitude: 0, longitude: 0, status: status)
        context.insert(event)
        return event
    }

    @MainActor
    private func addTrack(to event: EventModel, in context: ModelContext) -> TimelineTrack {
        let track = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true)
        track.event = event
        context.insert(track)
        return track
    }

    @MainActor
    @discardableResult
    private func addBlock(
        title: String,
        minutesFromNow: Double = 0,
        status: BlockStatus = .upcoming,
        to track: TimelineTrack,
        in context: ModelContext
    ) -> TimeBlockModel {
        let start = Date.now.addingTimeInterval(minutesFromNow * 60)
        let block = TimeBlockModel(
            title: title,
            scheduledStart: start,
            originalStart: start,
            duration: 1800
        )
        block.status = status
        block.track = track
        context.insert(block)
        return block
    }

    // MARK: - AC 1: Event status transitions from .planning to .live

    @Test @MainActor
    func eventStatusTransitionsFromPlanningToLive() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let event = makeEvent(status: .planning, in: context)
        try context.save()

        event.applyGoLiveMutation()

        #expect(event.status == .live)
        #expect(event.wentLiveAt != nil)
    }

    // MARK: - AC 2: First incomplete block becomes .active

    @Test @MainActor
    func firstIncompleteBlockBecomesActive() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let event = makeEvent(in: context)
        let track = addTrack(to: event, in: context)
        let first = addBlock(title: "Ceremony", minutesFromNow: 0, to: track, in: context)
        let second = addBlock(title: "Reception", minutesFromNow: 60, to: track, in: context)
        try context.save()

        event.applyGoLiveMutation()

        #expect(first.status == .active)
        #expect(second.status == .upcoming)
    }

    // MARK: - AC 3: Subsequent incomplete blocks are reset to .upcoming

    @Test @MainActor
    func subsequentIncompleteBlocksResetToUpcoming() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let event = makeEvent(in: context)
        let track = addTrack(to: event, in: context)
        let b1 = addBlock(title: "Block 1", minutesFromNow: 0, to: track, in: context)
        let b2 = addBlock(title: "Block 2", minutesFromNow: 30, to: track, in: context)
        let b3 = addBlock(title: "Block 3", minutesFromNow: 60, to: track, in: context)
        try context.save()

        event.applyGoLiveMutation()

        #expect(b1.status == .active)
        #expect(b2.status == .upcoming)
        #expect(b3.status == .upcoming)
    }

    // MARK: - AC 4: Pre-existing .completed blocks are preserved

    @Test @MainActor
    func completedBlocksArePreservedAndNotReset() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let event = makeEvent(in: context)
        let track = addTrack(to: event, in: context)
        let done = addBlock(title: "Done", minutesFromNow: 0, status: .completed, to: track, in: context)
        let next = addBlock(title: "Next", minutesFromNow: 30, to: track, in: context)
        try context.save()

        event.applyGoLiveMutation()

        #expect(done.status == .completed)
        #expect(next.status == .active)
    }

    // MARK: - AC 5: Second Go Live call is idempotent

    @Test @MainActor
    func goLiveIsIdempotentWhenCalledTwice() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let event = makeEvent(in: context)
        let track = addTrack(to: event, in: context)
        let first = addBlock(title: "Ceremony", minutesFromNow: 0, to: track, in: context)
        let second = addBlock(title: "Reception", minutesFromNow: 60, to: track, in: context)
        try context.save()

        event.applyGoLiveMutation()
        event.applyGoLiveMutation()

        #expect(event.status == .live)
        #expect(first.status == .active)
        #expect(second.status == .upcoming)
    }
}
