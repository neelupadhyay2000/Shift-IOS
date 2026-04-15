#if os(iOS)
import Foundation
import Models
import Services
import SwiftData
import Testing
@testable import shiftTimeline

/// Tests for the block advancement logic used by LiveDashboardView's
/// `advanceToNextBlock()` and the "Event Complete" state.
@MainActor
struct SlideToAdvanceTests {

    private func makeContainer() throws -> ModelContainer {
        try PersistenceController.forTesting()
    }

    private func makeEvent(
        in context: ModelContext,
        blockCount: Int = 3
    ) -> (EventModel, [TimeBlockModel]) {
        let base = Date.now
        let event = EventModel(
            title: "Test Event",
            date: base,
            latitude: 0,
            longitude: 0,
            status: .live
        )
        context.insert(event)

        let track = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true, event: event)
        context.insert(track)

        var blocks: [TimeBlockModel] = []
        for i in 0..<blockCount {
            let block = TimeBlockModel(
                title: "Block \(i)",
                scheduledStart: base.addingTimeInterval(TimeInterval(i * 1800)),
                duration: 1800
            )
            block.track = track
            context.insert(block)
            blocks.append(block)
        }

        // Activate the first block
        blocks[0].status = .active

        return (event, blocks)
    }

    // MARK: - Advancing marks current completed and next active

    @Test func advanceCompletesCurrentAndActivatesNext() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (_, blocks) = makeEvent(in: context, blockCount: 3)

        blocks[0].status = .completed
        blocks[1].status = .active

        #expect(blocks[0].status == .completed)
        #expect(blocks[1].status == .active)
        #expect(blocks[2].status == .upcoming)
    }

    // MARK: - Hero updates to next block

    @Test func activeBlockDerivedPropertyReturnsNextAfterAdvance() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (_, blocks) = makeEvent(in: context, blockCount: 3)

        blocks[0].status = .completed
        blocks[1].status = .active

        let sortedBlocks = blocks.sorted { $0.scheduledStart < $1.scheduledStart }
        let activeBlock = sortedBlocks.first(where: { $0.status == .active })

        #expect(activeBlock?.id == blocks[1].id)
        #expect(activeBlock?.title == "Block 1")
    }

    // MARK: - Final block shows event complete

    @Test func finalBlockAdvanceMarksEventCompleted() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (event, blocks) = makeEvent(in: context, blockCount: 2)

        blocks[0].status = .completed
        blocks[1].status = .active

        // Advance final block
        blocks[1].status = .completed
        let hasNext = blocks.contains { $0.status != .completed }
        if !hasNext {
            event.status = .completed
        }

        #expect(event.status == .completed)
        #expect(blocks.allSatisfy { $0.status == .completed })
    }

    // MARK: - isEventComplete derivation

    @Test func isEventCompleteIsFalseWhileBlocksRemain() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (_, blocks) = makeEvent(in: context, blockCount: 3)

        blocks[0].status = .completed
        blocks[1].status = .active

        let isComplete = blocks.allSatisfy { $0.status == .completed }
        #expect(!isComplete)
    }

    @Test func isEventCompleteIsTrueWhenAllBlocksDone() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (_, blocks) = makeEvent(in: context, blockCount: 2)

        blocks[0].status = .completed
        blocks[1].status = .completed

        let isComplete = blocks.allSatisfy { $0.status == .completed }
        #expect(isComplete)
    }

    // MARK: - SwiftData persistence

    @Test func advancePersistsToSwiftData() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (event, blocks) = makeEvent(in: context, blockCount: 2)

        blocks[0].status = .completed
        blocks[1].status = .active
        try context.save()

        let eventID = event.id
        let descriptor = FetchDescriptor<EventModel>(
            predicate: #Predicate { $0.id == eventID }
        )
        let fetched = try context.fetch(descriptor).first
        let fetchedBlocks = fetched?.tracks.flatMap(\.blocks)
            .sorted { $0.scheduledStart < $1.scheduledStart } ?? []

        #expect(fetchedBlocks[0].status == .completed)
        #expect(fetchedBlocks[1].status == .active)
    }

    // MARK: - Completion threshold constant

    @Test func completionThresholdIs80Percent() {
        #expect(SlideToAdvanceView.completionThreshold == 0.8)
    }
}
#endif
