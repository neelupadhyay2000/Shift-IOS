#if os(iOS)
import Foundation
import Models
import Services
import SwiftData
import Testing
@testable import shiftTimeline

/// Tests for the block advancement logic used by LiveDashboardView's
/// `performAdvance()` and the "Event Complete" state.
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

        blocks[0].status = .active

        return (event, blocks)
    }

    /// Derives active/next block the same way LiveDashboardView does.
    private func deriveActiveAndNext(
        from blocks: [TimeBlockModel]
    ) -> (active: TimeBlockModel?, next: TimeBlockModel?) {
        let sorted = blocks.sorted { $0.scheduledStart < $1.scheduledStart }
        let active = sorted.first(where: { $0.status == .active })
            ?? sorted.first(where: { $0.status != .completed })
        guard let active,
              let activeIndex = sorted.firstIndex(where: { $0.id == active.id })
        else {
            let next = sorted.first(where: { $0.status == .upcoming })
            return (active, next)
        }
        let tail = sorted.suffix(from: sorted.index(after: activeIndex))
        let next = tail.first(where: { $0.status != .completed })
        return (active, next)
    }

    // MARK: - Advancing via production code path

    @Test func advanceCompletesCurrentAndActivatesNext() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (event, blocks) = makeEvent(in: context, blockCount: 3)

        let (active, next) = deriveActiveAndNext(from: blocks)
        LiveDashboardView.performAdvance(activeBlock: active, nextBlock: next, event: event)

        #expect(blocks[0].status == .completed)
        #expect(blocks[1].status == .active)
        #expect(blocks[2].status == .upcoming)
    }

    // MARK: - Hero updates to next block

    @Test func activeBlockDerivedPropertyReturnsNextAfterAdvance() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (event, blocks) = makeEvent(in: context, blockCount: 3)

        let (active, next) = deriveActiveAndNext(from: blocks)
        LiveDashboardView.performAdvance(activeBlock: active, nextBlock: next, event: event)

        let (newActive, _) = deriveActiveAndNext(from: blocks)
        #expect(newActive?.id == blocks[1].id)
        #expect(newActive?.title == "Block 1")
    }

    // MARK: - Final block shows event complete

    @Test func finalBlockAdvanceMarksEventCompleted() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (event, blocks) = makeEvent(in: context, blockCount: 2)

        // Advance first block
        let (active1, next1) = deriveActiveAndNext(from: blocks)
        LiveDashboardView.performAdvance(activeBlock: active1, nextBlock: next1, event: event)

        // Advance final block
        let (active2, next2) = deriveActiveAndNext(from: blocks)
        LiveDashboardView.performAdvance(activeBlock: active2, nextBlock: next2, event: event)

        #expect(event.status == .completed)
        #expect(blocks.allSatisfy { $0.status == .completed })
    }

    // MARK: - isEventComplete derivation

    @Test func isEventCompleteIsFalseWhileBlocksRemain() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (event, blocks) = makeEvent(in: context, blockCount: 3)

        let (active, next) = deriveActiveAndNext(from: blocks)
        LiveDashboardView.performAdvance(activeBlock: active, nextBlock: next, event: event)

        let isComplete = blocks.allSatisfy { $0.status == .completed }
        #expect(!isComplete)
    }

    @Test func isEventCompleteIsTrueWhenAllBlocksDone() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (event, blocks) = makeEvent(in: context, blockCount: 2)

        // Advance both blocks via production path
        for _ in 0..<2 {
            let (active, next) = deriveActiveAndNext(from: blocks)
            LiveDashboardView.performAdvance(activeBlock: active, nextBlock: next, event: event)
        }

        let isComplete = blocks.allSatisfy { $0.status == .completed }
        #expect(isComplete)
    }

    // MARK: - SwiftData persistence

    @Test func advancePersistsToSwiftData() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (event, blocks) = makeEvent(in: context, blockCount: 2)

        let (active, next) = deriveActiveAndNext(from: blocks)
        LiveDashboardView.performAdvance(activeBlock: active, nextBlock: next, event: event)
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

    // MARK: - No-op when no active block

    @Test func advanceWithNoActiveBlockIsNoOp() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (event, blocks) = makeEvent(in: context, blockCount: 2)

        // Reset all to upcoming (no active)
        blocks[0].status = .upcoming

        LiveDashboardView.performAdvance(activeBlock: nil, nextBlock: blocks[0], event: event)

        #expect(blocks[0].status == .upcoming)
        #expect(event.status == .live)
    }
}
#endif
