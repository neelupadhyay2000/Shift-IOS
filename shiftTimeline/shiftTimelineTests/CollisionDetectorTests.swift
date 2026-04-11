import Engine
import Foundation
import Models
import Testing

struct CollisionDetectorTests {

    // MARK: - Placeholder Behaviour

    @Test @MainActor func detectReturnsEmptyForEmptyBlocks() {
        let detector = CollisionDetector()

        let result = detector.detect(blocks: [])

        #expect(result.isEmpty)
    }

    @Test @MainActor func detectReturnsEmptyForSingleBlock() {
        let detector = CollisionDetector()
        let block = TimeBlockModel(title: "Solo", scheduledStart: Date(), duration: 1800)

        let result = detector.detect(blocks: [block])

        #expect(result.isEmpty)
    }

    @Test @MainActor func detectReturnsEmptyForAllFluidNonOverlappingBlocks() {
        let detector = CollisionDetector()
        let start = Date()

        let blocks = [
            TimeBlockModel(title: "Block1", scheduledStart: start, duration: 600),
            TimeBlockModel(title: "Block2", scheduledStart: start.addingTimeInterval(600), duration: 600),
            TimeBlockModel(title: "Block3", scheduledStart: start.addingTimeInterval(1200), duration: 600)
        ]

        let result = detector.detect(blocks: blocks)

        #expect(result.isEmpty)
    }

    @Test @MainActor func detectReturnsEmptyForAllPinnedBlocks() {
        let detector = CollisionDetector()
        let start = Date()

        let blocks = [
            TimeBlockModel(title: "Pinned1", scheduledStart: start, duration: 600, isPinned: true),
            TimeBlockModel(title: "Pinned2", scheduledStart: start.addingTimeInterval(600), duration: 600, isPinned: true)
        ]

        let result = detector.detect(blocks: blocks)

        #expect(result.isEmpty)
    }

    @Test @MainActor func detectReturnsEmptyForFluidAndPinnedNonOverlapping() {
        let detector = CollisionDetector()
        let start = Date()

        // Fluid ends exactly where Pinned begins — no overlap
        let blocks = [
            TimeBlockModel(title: "Fluid", scheduledStart: start, duration: 600),
            TimeBlockModel(title: "Pinned", scheduledStart: start.addingTimeInterval(600), duration: 600, isPinned: true)
        ]

        let result = detector.detect(blocks: blocks)

        #expect(result.isEmpty)
    }

    // MARK: - Collision Struct

    @Test func collisionStoresFlatProperties() {
        let fluidID = UUID()
        let pinnedID = UUID()
        let collision = Collision(fluidBlockID: fluidID, pinnedBlockID: pinnedID, overlapMinutes: 5)

        #expect(collision.fluidBlockID == fluidID)
        #expect(collision.pinnedBlockID == pinnedID)
        #expect(collision.overlapMinutes == 5)
    }

    @Test func collisionConformsToEquatable() {
        let fluidID = UUID()
        let pinnedID = UUID()
        let a = Collision(fluidBlockID: fluidID, pinnedBlockID: pinnedID, overlapMinutes: 3)
        let b = Collision(fluidBlockID: fluidID, pinnedBlockID: pinnedID, overlapMinutes: 3)
        let c = Collision(fluidBlockID: fluidID, pinnedBlockID: pinnedID, overlapMinutes: 7)

        #expect(a == b)
        #expect(a != c)
    }

    @Test func collisionDetectorConformsToSendable() {
        let detector = CollisionDetector()
        let _: any Sendable = detector
        _ = detector
    }

    @Test func collisionConformsToSendable() {
        let collision = Collision(fluidBlockID: UUID(), pinnedBlockID: UUID(), overlapMinutes: 1)
        let _: any Sendable = collision
        _ = collision
    }
}
