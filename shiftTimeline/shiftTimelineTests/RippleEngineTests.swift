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
}
