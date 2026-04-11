import Engine
import Foundation
import Models
import Testing

struct RippleEngineTests {

    @Test @MainActor func recalculateReturnsCleanResult() {
        let engine = RippleEngine()

        let block = TimeBlockModel(
            title: "Ceremony",
            scheduledStart: Date(),
            duration: 1800
        )

        let result = engine.recalculate(
            blocks: [block],
            changedBlockID: block.id,
            delta: 300
        )

        #expect(result.status == .clean)
        #expect(result.blocks.count == 1)
        #expect(result.collisions.isEmpty)
        #expect(result.compressedBlockIDs.isEmpty)
    }

    @Test func engineAcceptsCustomDependencies() {
        let engine = RippleEngine(
            dependencyResolver: DependencyResolver(),
            collisionDetector: CollisionDetector(),
            compressionCalculator: CompressionCalculator()
        )

        // Sendable conformance is enforced at compile time;
        // this assignment proves the type satisfies the constraint.
        let _: any Sendable = engine
        _ = engine
    }

    @Test @MainActor func recalculateReturnsUnchangedBlocksForZeroDelta() {
        let engine = RippleEngine()
        let start = Date()

        let blocks = [
            TimeBlockModel(title: "Setup", scheduledStart: start, duration: 900),
            TimeBlockModel(title: "Ceremony", scheduledStart: start.addingTimeInterval(900), duration: 1800)
        ]

        let result = engine.recalculate(
            blocks: blocks,
            changedBlockID: blocks[0].id,
            delta: 0
        )

        #expect(result.status == .clean)
        #expect(result.blocks.count == 2)
        #expect(result.blocks[0].scheduledStart == start)
        #expect(result.blocks[1].scheduledStart == start.addingTimeInterval(900))
    }

    // MARK: - Forward Shift Tests

    @Test @MainActor func forwardShiftFluidBlocksAfterChanged() {
        let engine = RippleEngine()
        let start = Date()
        let delta: TimeInterval = 15 * 60 // +15 minutes

        // 5 blocks: Fluid, Fluid, Fluid, Pinned, Pinned
        let blocks = [
            TimeBlockModel(title: "Block1", scheduledStart: start, duration: 600),
            TimeBlockModel(title: "Block2", scheduledStart: start.addingTimeInterval(600), duration: 600),
            TimeBlockModel(title: "Block3", scheduledStart: start.addingTimeInterval(1200), duration: 600),
            TimeBlockModel(title: "Block4", scheduledStart: start.addingTimeInterval(1800), duration: 600, isPinned: true),
            TimeBlockModel(title: "Block5", scheduledStart: start.addingTimeInterval(2400), duration: 600, isPinned: true)
        ]

        let result = engine.recalculate(
            blocks: blocks,
            changedBlockID: blocks[0].id,
            delta: delta
        )

        #expect(result.status == .clean)
        // Changed block shifts by delta
        #expect(result.blocks[0].scheduledStart == start.addingTimeInterval(delta))
        // Fluid blocks after changed block shift by delta
        #expect(result.blocks[1].scheduledStart == start.addingTimeInterval(600 + delta))
        #expect(result.blocks[2].scheduledStart == start.addingTimeInterval(1200 + delta))
        // Pinned blocks remain unchanged
        #expect(result.blocks[3].scheduledStart == start.addingTimeInterval(1800))
        #expect(result.blocks[4].scheduledStart == start.addingTimeInterval(2400))
    }

    @Test @MainActor func forwardShiftMiddleBlockOnlyAffectsSubsequent() {
        let engine = RippleEngine()
        let start = Date()
        let delta: TimeInterval = 10 * 60 // +10 minutes

        let blocks = [
            TimeBlockModel(title: "Before", scheduledStart: start, duration: 600),
            TimeBlockModel(title: "Changed", scheduledStart: start.addingTimeInterval(600), duration: 600),
            TimeBlockModel(title: "After", scheduledStart: start.addingTimeInterval(1200), duration: 600)
        ]

        let result = engine.recalculate(
            blocks: blocks,
            changedBlockID: blocks[1].id,
            delta: delta
        )

        // Block before changed is unaffected
        #expect(result.blocks[0].scheduledStart == start)
        // Changed block shifts by delta
        #expect(result.blocks[1].scheduledStart == start.addingTimeInterval(600 + delta))
        // Block after changed shifts by delta
        #expect(result.blocks[2].scheduledStart == start.addingTimeInterval(1200 + delta))
    }

    @Test @MainActor func forwardShiftAllPinnedExceptChangedOnlyMovesChanged() {
        let engine = RippleEngine()
        let start = Date()
        let delta: TimeInterval = 5 * 60 // +5 minutes

        let blocks = [
            TimeBlockModel(title: "Pinned1", scheduledStart: start, duration: 600, isPinned: true),
            TimeBlockModel(title: "Changed", scheduledStart: start.addingTimeInterval(600), duration: 600),
            TimeBlockModel(title: "Pinned2", scheduledStart: start.addingTimeInterval(1200), duration: 600, isPinned: true),
            TimeBlockModel(title: "Pinned3", scheduledStart: start.addingTimeInterval(1800), duration: 600, isPinned: true)
        ]

        let result = engine.recalculate(
            blocks: blocks,
            changedBlockID: blocks[1].id,
            delta: delta
        )

        // All pinned blocks unchanged
        #expect(result.blocks[0].scheduledStart == start)
        #expect(result.blocks[2].scheduledStart == start.addingTimeInterval(1200))
        #expect(result.blocks[3].scheduledStart == start.addingTimeInterval(1800))
        // Only the changed block moves
        #expect(result.blocks[1].scheduledStart == start.addingTimeInterval(600 + delta))
    }

    // MARK: - Backward Shift Tests

    @Test @MainActor func backwardShiftClampsToOriginalStart() {
        let engine = RippleEngine()
        let originalStart = Date()
        let drift: TimeInterval = 5 * 60 // blocks have drifted +5 min from original
        let delta: TimeInterval = -10 * 60 // shift back by -10 min (exceeds drift)

        // Blocks whose scheduledStart is 5 min ahead of originalStart
        let blocks = [
            TimeBlockModel(
                title: "Block1",
                scheduledStart: originalStart.addingTimeInterval(drift),
                originalStart: originalStart,
                duration: 600
            ),
            TimeBlockModel(
                title: "Block2",
                scheduledStart: originalStart.addingTimeInterval(600 + drift),
                originalStart: originalStart.addingTimeInterval(600),
                duration: 600
            ),
            TimeBlockModel(
                title: "Block3",
                scheduledStart: originalStart.addingTimeInterval(1200 + drift),
                originalStart: originalStart.addingTimeInterval(1200),
                duration: 600
            )
        ]

        let result = engine.recalculate(
            blocks: blocks,
            changedBlockID: blocks[0].id,
            delta: delta
        )

        // No block should go earlier than its originalStart
        for block in result.blocks {
            #expect(block.scheduledStart >= block.originalStart)
        }
        // Changed block clamped to originalStart (drift=5min, delta=-10min)
        #expect(result.blocks[0].scheduledStart == originalStart)
        // Subsequent fluid blocks also clamped
        #expect(result.blocks[1].scheduledStart == originalStart.addingTimeInterval(600))
        #expect(result.blocks[2].scheduledStart == originalStart.addingTimeInterval(1200))
    }

    @Test @MainActor func backwardShiftLargeDeltaClampsAllToOriginalStart() {
        let engine = RippleEngine()
        let originalStart = Date()
        let drift: TimeInterval = 20 * 60 // blocks drifted +20 min
        let delta: TimeInterval = -60 * 60 // shift back by -60 min (far exceeds drift)

        let blocks = [
            TimeBlockModel(
                title: "Block1",
                scheduledStart: originalStart.addingTimeInterval(drift),
                originalStart: originalStart,
                duration: 600
            ),
            TimeBlockModel(
                title: "Block2",
                scheduledStart: originalStart.addingTimeInterval(600 + drift),
                originalStart: originalStart.addingTimeInterval(600),
                duration: 600
            ),
            TimeBlockModel(
                title: "Block3",
                scheduledStart: originalStart.addingTimeInterval(1200 + drift),
                originalStart: originalStart.addingTimeInterval(1200),
                duration: 600
            )
        ]

        let result = engine.recalculate(
            blocks: blocks,
            changedBlockID: blocks[0].id,
            delta: delta
        )

        // All Fluid blocks clamp to their originalStart
        #expect(result.blocks[0].scheduledStart == originalStart)
        #expect(result.blocks[1].scheduledStart == originalStart.addingTimeInterval(600))
        #expect(result.blocks[2].scheduledStart == originalStart.addingTimeInterval(1200))
    }

    @Test @MainActor func backwardShiftPinnedBlocksUnchanged() {
        let engine = RippleEngine()
        let originalStart = Date()
        let drift: TimeInterval = 10 * 60
        let delta: TimeInterval = -5 * 60

        let blocks = [
            TimeBlockModel(
                title: "Changed",
                scheduledStart: originalStart.addingTimeInterval(drift),
                originalStart: originalStart,
                duration: 600
            ),
            TimeBlockModel(
                title: "Pinned1",
                scheduledStart: originalStart.addingTimeInterval(600 + drift),
                originalStart: originalStart.addingTimeInterval(600),
                duration: 600,
                isPinned: true
            ),
            TimeBlockModel(
                title: "Pinned2",
                scheduledStart: originalStart.addingTimeInterval(1200 + drift),
                originalStart: originalStart.addingTimeInterval(1200),
                duration: 600,
                isPinned: true
            )
        ]

        let result = engine.recalculate(
            blocks: blocks,
            changedBlockID: blocks[0].id,
            delta: delta
        )

        // Changed block shifts back by delta (within drift, no clamping needed)
        #expect(result.blocks[0].scheduledStart == originalStart.addingTimeInterval(drift + delta))
        // Pinned blocks remain completely unchanged
        #expect(result.blocks[1].scheduledStart == originalStart.addingTimeInterval(600 + drift))
        #expect(result.blocks[2].scheduledStart == originalStart.addingTimeInterval(1200 + drift))
    }

    // MARK: - Pinned Block Cannot Shift

    @Test @MainActor func pinnedBlockCannotShift() {
        let engine = RippleEngine()
        let start = Date()

        let blocks = [
            TimeBlockModel(title: "Fluid", scheduledStart: start, duration: 600),
            TimeBlockModel(title: "Pinned", scheduledStart: start.addingTimeInterval(600), duration: 600, isPinned: true),
            TimeBlockModel(title: "Fluid2", scheduledStart: start.addingTimeInterval(1200), duration: 600)
        ]

        let result = engine.recalculate(
            blocks: blocks,
            changedBlockID: blocks[1].id,
            delta: 300
        )

        #expect(result.status == .pinnedBlockCannotShift)
        #expect(result.blocks.count == blocks.count)
        for (original, returned) in zip(blocks, result.blocks) {
            #expect(original.id == returned.id)
            #expect(original.scheduledStart == returned.scheduledStart)
        }
        #expect(result.collisions.isEmpty)
    }

    // MARK: - Last Block Shift

    @Test @MainActor func shiftLastBlockOnlyMovesItself() {
        let engine = RippleEngine()
        let start = Date()
        let delta: TimeInterval = 20 * 60 // +20 minutes

        let blocks = [
            TimeBlockModel(title: "Block1", scheduledStart: start, duration: 600),
            TimeBlockModel(title: "Block2", scheduledStart: start.addingTimeInterval(600), duration: 600),
            TimeBlockModel(title: "Block3", scheduledStart: start.addingTimeInterval(1200), duration: 600),
            TimeBlockModel(title: "Block4", scheduledStart: start.addingTimeInterval(1800), duration: 600),
            TimeBlockModel(title: "Block5", scheduledStart: start.addingTimeInterval(2400), duration: 600)
        ]

        let result = engine.recalculate(
            blocks: blocks,
            changedBlockID: blocks[4].id,
            delta: delta
        )

        #expect(result.status == .clean)
        // All preceding blocks unchanged
        #expect(result.blocks[0].scheduledStart == start)
        #expect(result.blocks[1].scheduledStart == start.addingTimeInterval(600))
        #expect(result.blocks[2].scheduledStart == start.addingTimeInterval(1200))
        #expect(result.blocks[3].scheduledStart == start.addingTimeInterval(1800))
        // Only the last block shifts
        #expect(result.blocks[4].scheduledStart == start.addingTimeInterval(2400 + delta))
    }

    // MARK: - Edge Cases

    @Test func emptyBlocksReturnsClean() {
        let engine = RippleEngine()

        let result = engine.recalculate(
            blocks: [],
            changedBlockID: UUID(),
            delta: 300
        )

        #expect(result.status == .clean)
        #expect(result.blocks.isEmpty)
        #expect(result.collisions.isEmpty)
        #expect(result.compressedBlockIDs.isEmpty)
    }

    @Test @MainActor func unknownBlockIDReturnsClean() {
        let engine = RippleEngine()
        let start = Date()

        let blocks = [
            TimeBlockModel(title: "Block1", scheduledStart: start, duration: 600),
            TimeBlockModel(title: "Block2", scheduledStart: start.addingTimeInterval(600), duration: 600)
        ]

        let result = engine.recalculate(
            blocks: blocks,
            changedBlockID: UUID(), // ID not in array
            delta: 300
        )

        #expect(result.status == .clean)
        #expect(result.blocks.count == 2)
        // Blocks unchanged
        #expect(result.blocks[0].scheduledStart == start)
        #expect(result.blocks[1].scheduledStart == start.addingTimeInterval(600))
        #expect(result.collisions.isEmpty)
    }
}
