import Engine
import Foundation
import Models
import Testing

struct CompressionCalculatorTests {

    @Test @MainActor func compressReturnsBlocksUnchanged() {
        let calculator = CompressionCalculator()
        let start = Date()

        let blocks = [
            TimeBlockModel(title: "Block1", scheduledStart: start, duration: 600, minimumDuration: 300),
            TimeBlockModel(title: "Block2", scheduledStart: start.addingTimeInterval(600), duration: 600, minimumDuration: 300),
            TimeBlockModel(title: "Pinned", scheduledStart: start.addingTimeInterval(1200), duration: 600, isPinned: true)
        ]

        let collision = Collision(
            fluidBlockID: blocks[1].id,
            pinnedBlockID: blocks[2].id,
            overlapMinutes: 5
        )

        let result = calculator.compress(blocks: blocks, collision: collision)

        #expect(result.count == blocks.count)
        for (original, returned) in zip(blocks, result) {
            #expect(original.id == returned.id)
            #expect(original.scheduledStart == returned.scheduledStart)
            #expect(original.duration == returned.duration)
        }
    }

    @Test func compressionCalculatorIsSendable() {
        let calculator = CompressionCalculator()
        let _: any Sendable = calculator
        _ = calculator
    }
}
