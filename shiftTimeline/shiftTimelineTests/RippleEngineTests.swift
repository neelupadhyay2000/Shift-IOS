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

        #expect(engine is Sendable)
    }

    @Test @MainActor func recalculateReturnsUnchangedBlocks() {
        let engine = RippleEngine()
        let start = Date()

        let blocks = [
            TimeBlockModel(title: "Setup", scheduledStart: start, duration: 900),
            TimeBlockModel(title: "Ceremony", scheduledStart: start.addingTimeInterval(900), duration: 1800)
        ]

        let result = engine.recalculate(
            blocks: blocks,
            changedBlockID: blocks[0].id,
            delta: 600
        )

        #expect(result.status == .clean)
        #expect(result.blocks.count == 2)
        #expect(result.blocks[0].title == "Setup")
        #expect(result.blocks[1].title == "Ceremony")
    }
}
