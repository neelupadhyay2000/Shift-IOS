import Engine
import Foundation
import Models
import Testing

struct CompressionCalculatorTests {

    // MARK: - Equal Duration Compression

    /// 3 blocks × 30 min in a 60-min gap → each compressed to 20 min.
    @Test @MainActor func equalBlocksCompressedProportionally() {
        let calculator = CompressionCalculator()
        let start = Date()
        let thirtyMin: TimeInterval = 30 * 60
        let sixtyMin: TimeInterval = 60 * 60

        let blocks = [
            TimeBlockModel(title: "A", scheduledStart: start, duration: thirtyMin),
            TimeBlockModel(title: "B", scheduledStart: start.addingTimeInterval(thirtyMin), duration: thirtyMin),
            TimeBlockModel(title: "C", scheduledStart: start.addingTimeInterval(2 * thirtyMin), duration: thirtyMin),
            TimeBlockModel(title: "Pinned", scheduledStart: start.addingTimeInterval(sixtyMin), duration: thirtyMin, isPinned: true)
        ]

        let collision = Collision(
            fluidBlockID: blocks[2].id,
            pinnedBlockID: blocks[3].id,
            overlapMinutes: 30
        )

        let result = calculator.compress(blocks: blocks, collision: collision)

        let expectedDuration: TimeInterval = 20 * 60

        #expect(result.blocks[0].duration == expectedDuration)
        #expect(result.blocks[1].duration == expectedDuration)
        #expect(result.blocks[2].duration == expectedDuration)

        let totalCompressed = result.blocks[0].duration + result.blocks[1].duration + result.blocks[2].duration
        #expect(totalCompressed == sixtyMin)
        #expect(result.status == .hasCollisions)
    }

    // MARK: - Contiguous Scheduled Starts

    @Test @MainActor func compressedBlocksHaveContiguousScheduledStarts() {
        let calculator = CompressionCalculator()
        let start = Date()
        let thirtyMin: TimeInterval = 30 * 60
        let sixtyMin: TimeInterval = 60 * 60

        let blocks = [
            TimeBlockModel(title: "A", scheduledStart: start, duration: thirtyMin),
            TimeBlockModel(title: "B", scheduledStart: start.addingTimeInterval(thirtyMin), duration: thirtyMin),
            TimeBlockModel(title: "C", scheduledStart: start.addingTimeInterval(2 * thirtyMin), duration: thirtyMin),
            TimeBlockModel(title: "Pinned", scheduledStart: start.addingTimeInterval(sixtyMin), duration: thirtyMin, isPinned: true)
        ]

        let collision = Collision(
            fluidBlockID: blocks[2].id,
            pinnedBlockID: blocks[3].id,
            overlapMinutes: 30
        )

        let result = calculator.compress(blocks: blocks, collision: collision)

        #expect(result.blocks[0].scheduledStart == start)
        #expect(result.blocks[1].scheduledStart == result.blocks[0].scheduledStart.addingTimeInterval(result.blocks[0].duration))
        #expect(result.blocks[2].scheduledStart == result.blocks[1].scheduledStart.addingTimeInterval(result.blocks[1].duration))
        let lastEnd = result.blocks[2].scheduledStart.addingTimeInterval(result.blocks[2].duration)
        #expect(lastEnd == result.blocks[3].scheduledStart)
    }

    // MARK: - Unequal Duration Proportional Compression

    @Test @MainActor func unequalDurationsCompressedProportionally() {
        let calculator = CompressionCalculator()
        let start = Date()
        let availableGap: TimeInterval = 60 * 60

        let blocks2 = [
            TimeBlockModel(title: "Long", scheduledStart: start, duration: 60 * 60),
            TimeBlockModel(title: "Short", scheduledStart: start.addingTimeInterval(60 * 60), duration: 30 * 60),
            TimeBlockModel(title: "Pinned", scheduledStart: start.addingTimeInterval(availableGap), duration: 1800, isPinned: true)
        ]

        let collision2 = Collision(
            fluidBlockID: blocks2[1].id,
            pinnedBlockID: blocks2[2].id,
            overlapMinutes: 30
        )

        let result2 = calculator.compress(blocks: blocks2, collision: collision2)

        let expectedLong: TimeInterval = 40 * 60
        let expectedShort: TimeInterval = 20 * 60

        #expect(result2.blocks[0].duration == expectedLong)
        #expect(result2.blocks[1].duration == expectedShort)

        let total = result2.blocks[0].duration + result2.blocks[1].duration
        #expect(total == availableGap)

        #expect(result2.blocks[1].scheduledStart == result2.blocks[0].scheduledStart.addingTimeInterval(result2.blocks[0].duration))
    }

    // MARK: - Pinned Block Unchanged

    @Test @MainActor func pinnedBlockUnchangedAfterCompression() {
        let calculator = CompressionCalculator()
        let start = Date()
        let pinnedStart = start.addingTimeInterval(60 * 60)
        let pinnedDuration: TimeInterval = 1800

        let blocks = [
            TimeBlockModel(title: "A", scheduledStart: start, duration: 45 * 60),
            TimeBlockModel(title: "B", scheduledStart: start.addingTimeInterval(45 * 60), duration: 45 * 60),
            TimeBlockModel(title: "Pinned", scheduledStart: pinnedStart, duration: pinnedDuration, isPinned: true)
        ]

        let collision = Collision(
            fluidBlockID: blocks[1].id,
            pinnedBlockID: blocks[2].id,
            overlapMinutes: 30
        )

        let result = calculator.compress(blocks: blocks, collision: collision)

        #expect(result.blocks[2].scheduledStart == pinnedStart)
        #expect(result.blocks[2].duration == pinnedDuration)
    }

    // MARK: - Minimum Duration Protection

    /// Block A (30 min, min 25) + Block B (30 min, min 10) in 40-min gap → A=25, B=15
    @Test @MainActor func minimumDurationProtection() {
        let calculator = CompressionCalculator()
        let start = Date()
        let thirtyMin: TimeInterval = 30 * 60
        let fortyMin: TimeInterval = 40 * 60

        let blocks = [
            TimeBlockModel(title: "A", scheduledStart: start, duration: thirtyMin, minimumDuration: 25 * 60),
            TimeBlockModel(title: "B", scheduledStart: start.addingTimeInterval(thirtyMin), duration: thirtyMin, minimumDuration: 10 * 60),
            TimeBlockModel(title: "Pinned", scheduledStart: start.addingTimeInterval(fortyMin), duration: 1800, isPinned: true)
        ]

        let collision = Collision(
            fluidBlockID: blocks[1].id,
            pinnedBlockID: blocks[2].id,
            overlapMinutes: 20
        )

        let result = calculator.compress(blocks: blocks, collision: collision)

        #expect(result.blocks[0].duration == 25 * 60)
        #expect(result.blocks[1].duration == 15 * 60)
        #expect(result.blocks[0].duration >= 25 * 60)
        #expect(result.blocks[1].duration >= 10 * 60)
        #expect(result.blocks[0].duration + result.blocks[1].duration == fortyMin)
    }

    /// No block ever has duration < minimumDuration after compression.
    @Test @MainActor func noBlockBelowMinimumDuration() {
        let calculator = CompressionCalculator()
        let start = Date()

        let blocks = [
            TimeBlockModel(title: "A", scheduledStart: start, duration: 40 * 60, minimumDuration: 15 * 60),
            TimeBlockModel(title: "B", scheduledStart: start.addingTimeInterval(40 * 60), duration: 30 * 60, minimumDuration: 15 * 60),
            TimeBlockModel(title: "C", scheduledStart: start.addingTimeInterval(70 * 60), duration: 20 * 60, minimumDuration: 10 * 60),
            TimeBlockModel(title: "Pinned", scheduledStart: start.addingTimeInterval(60 * 60), duration: 1800, isPinned: true)
        ]

        let collision = Collision(
            fluidBlockID: blocks[2].id,
            pinnedBlockID: blocks[3].id,
            overlapMinutes: 30
        )

        let result = calculator.compress(blocks: blocks, collision: collision)

        for block in result.blocks where !block.isPinned {
            #expect(block.duration >= block.minimumDuration)
        }
    }

    // MARK: - Impossible Compression

    /// 3 blocks min 15 each (45 min total) in 30-min gap → impossible.
    @Test @MainActor func impossibleCompressionFlagged() {
        let calculator = CompressionCalculator()
        let start = Date()
        let fifteenMin: TimeInterval = 15 * 60
        let tenMin: TimeInterval = 10 * 60
        let thirtyMin: TimeInterval = 30 * 60

        let blocks = [
            TimeBlockModel(title: "A", scheduledStart: start, duration: 20 * 60, minimumDuration: fifteenMin),
            TimeBlockModel(title: "B", scheduledStart: start.addingTimeInterval(tenMin), duration: 20 * 60, minimumDuration: fifteenMin),
            TimeBlockModel(title: "C", scheduledStart: start.addingTimeInterval(20 * 60), duration: 20 * 60, minimumDuration: fifteenMin),
            TimeBlockModel(title: "Pinned", scheduledStart: start.addingTimeInterval(thirtyMin), duration: 1800, isPinned: true)
        ]

        let collision = Collision(
            fluidBlockID: blocks[2].id,
            pinnedBlockID: blocks[3].id,
            overlapMinutes: 30
        )

        let result = calculator.compress(blocks: blocks, collision: collision)

        #expect(result.status == .impossible)

        // All trapped blocks set to minimumDuration
        for block in result.blocks where !block.isPinned {
            #expect(block.duration == block.minimumDuration)
            #expect(block.requiresReview == true)
        }
    }

    /// 2 blocks min 15 each in 30-min gap → exactly fits, NOT impossible.
    @Test @MainActor func exactFitIsNotImpossible() {
        let calculator = CompressionCalculator()
        let start = Date()
        let fifteenMin: TimeInterval = 15 * 60
        let thirtyMin: TimeInterval = 30 * 60

        let blocks = [
            TimeBlockModel(title: "A", scheduledStart: start, duration: 20 * 60, minimumDuration: fifteenMin),
            TimeBlockModel(title: "B", scheduledStart: start.addingTimeInterval(20 * 60), duration: 20 * 60, minimumDuration: fifteenMin),
            TimeBlockModel(title: "Pinned", scheduledStart: start.addingTimeInterval(thirtyMin), duration: 1800, isPinned: true)
        ]

        let collision = Collision(
            fluidBlockID: blocks[1].id,
            pinnedBlockID: blocks[2].id,
            overlapMinutes: 10
        )

        let result = calculator.compress(blocks: blocks, collision: collision)

        #expect(result.status == .hasCollisions)
        // Both blocks should fit — no block needs review
        for block in result.blocks where !block.isPinned {
            #expect(block.duration >= block.minimumDuration)
        }
    }

    // MARK: - Sendable

    @Test func compressionCalculatorIsSendable() {
        let calculator = CompressionCalculator()
        let _: any Sendable = calculator
        _ = calculator
    }
}
