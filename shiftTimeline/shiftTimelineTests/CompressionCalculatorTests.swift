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

        // 3 Fluid blocks of 30 min each, then a Pinned block at +60 min.
        // Total fluid duration = 90 min, but only 60 min available.
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

        let expectedDuration: TimeInterval = 20 * 60 // 60 min / 3 blocks

        // Each block compressed to 20 min
        #expect(result[0].duration == expectedDuration)
        #expect(result[1].duration == expectedDuration)
        #expect(result[2].duration == expectedDuration)

        // Total compressed duration equals available gap exactly
        let totalCompressed = result[0].duration + result[1].duration + result[2].duration
        #expect(totalCompressed == sixtyMin)
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

        // First block starts at the original position
        #expect(result[0].scheduledStart == start)
        // Each subsequent block starts exactly where the previous one ends
        #expect(result[1].scheduledStart == result[0].scheduledStart.addingTimeInterval(result[0].duration))
        #expect(result[2].scheduledStart == result[1].scheduledStart.addingTimeInterval(result[1].duration))
        // Last compressed block ends exactly at the pinned block's start
        let lastEnd = result[2].scheduledStart.addingTimeInterval(result[2].duration)
        #expect(lastEnd == result[3].scheduledStart)
    }

    // MARK: - Unequal Duration Proportional Compression

    @Test @MainActor func unequalDurationsCompressedProportionally() {
        let calculator = CompressionCalculator()
        let start = Date()
        let availableGap: TimeInterval = 60 * 60 // 60 min

        // Block A = 40 min, Block B = 20 min → total 60 min of fluid, gap = 60 min
        // But let's make them overflow: A = 40 min, B = 40 min, C = 40 min → total = 120 min, gap = 60 min
        let fortyMin: TimeInterval = 40 * 60

        let blocks = [
            TimeBlockModel(title: "A", scheduledStart: start, duration: fortyMin),
            TimeBlockModel(title: "B", scheduledStart: start.addingTimeInterval(fortyMin), duration: fortyMin),
            TimeBlockModel(title: "C", scheduledStart: start.addingTimeInterval(2 * fortyMin), duration: fortyMin),
            TimeBlockModel(title: "Pinned", scheduledStart: start.addingTimeInterval(availableGap), duration: 1800, isPinned: true)
        ]

        // Now test with truly unequal: A = 60 min, B = 30 min in a 60 min gap
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

        // Total original duration = 90 min, available = 60 min
        // Long: (60/90) * 60 = 40 min
        // Short: (30/90) * 60 = 20 min
        let expectedLong: TimeInterval = 40 * 60
        let expectedShort: TimeInterval = 20 * 60

        #expect(result2[0].duration == expectedLong)
        #expect(result2[1].duration == expectedShort)

        // Total equals available gap
        let total = result2[0].duration + result2[1].duration
        #expect(total == availableGap)

        // Contiguous
        #expect(result2[1].scheduledStart == result2[0].scheduledStart.addingTimeInterval(result2[0].duration))
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

        #expect(result[2].scheduledStart == pinnedStart)
        #expect(result[2].duration == pinnedDuration)
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

        // A clamped to minimum 25 min, B gets remaining 15 min
        #expect(result[0].duration == 25 * 60)
        #expect(result[1].duration == 15 * 60)

        // No block below its minimum
        #expect(result[0].duration >= 25 * 60)
        #expect(result[1].duration >= 10 * 60)

        // Total equals available gap
        #expect(result[0].duration + result[1].duration == fortyMin)
    }

    /// No block ever has duration < minimumDuration after compression.
    @Test @MainActor func noBlockBelowMinimumDuration() {
        let calculator = CompressionCalculator()
        let start = Date()

        // 3 blocks with high minimums in a tight gap
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

        for block in result where !block.isPinned {
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
