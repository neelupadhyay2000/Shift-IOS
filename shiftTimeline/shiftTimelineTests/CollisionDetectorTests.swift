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

    // MARK: - Acceptance Criteria Tests (SHIFT-201)

    /// 3 Fluid blocks + 1 Pinned block; last Fluid has been shifted +30 min
    /// so it runs 30 min into the Pinned block → exactly 1 collision, overlapMinutes = 30.
    @Test @MainActor func detect_fluidOverlapsPinned_oneCollisionWithCorrectMinutes() {
        let detector = CollisionDetector()
        let start = Date()

        let fluid1 = TimeBlockModel(title: "Fluid1", scheduledStart: start, duration: 1800)
        let fluid2 = TimeBlockModel(title: "Fluid2", scheduledStart: start.addingTimeInterval(1800), duration: 1800)
        // Fluid3 shifted +30 min: starts at 3600+1800, ends at 3600+3600 = 7200
        let fluid3 = TimeBlockModel(
            title: "Fluid3",
            scheduledStart: start.addingTimeInterval(3600 + 1800), // shifted +30 min
            duration: 1800
        )
        // Pinned starts at 5400 (originally right after fluid3's unshifted end)
        let pinned = TimeBlockModel(
            title: "Pinned",
            scheduledStart: start.addingTimeInterval(5400),
            duration: 1800,
            isPinned: true
        )

        // fluid3 end = start + 5400 + 1800 = start + 7200
        // pinned start = start + 5400
        // overlap = 7200 - 5400 = 1800 s = 30 min
        let result = detector.detect(blocks: [fluid1, fluid2, fluid3, pinned])

        #expect(result.count == 1)
        #expect(result[0].fluidBlockID == fluid3.id)
        #expect(result[0].pinnedBlockID == pinned.id)
        #expect(result[0].overlapMinutes == 30)
    }

    /// Fluid ends exactly at Pinned start (overlap = 0 s) → no collision.
    @Test @MainActor func detect_fluidEndsExactlyAtPinnedStart_noCollision() {
        let detector = CollisionDetector()
        let start = Date()

        let fluid = TimeBlockModel(title: "Fluid", scheduledStart: start, duration: 1800)
        // Pinned starts exactly when fluid ends
        let pinned = TimeBlockModel(
            title: "Pinned",
            scheduledStart: start.addingTimeInterval(1800),
            duration: 1800,
            isPinned: true
        )

        let result = detector.detect(blocks: [fluid, pinned])

        #expect(result.isEmpty)
    }

    /// Fluid ends 1 second after Pinned start (overlap = 1 s, overlapMinutes = 0) → collision detected.
    @Test @MainActor func detect_fluidEndsOneSecondAfterPinnedStart_collisionDetected() {
        let detector = CollisionDetector()
        let start = Date()

        // Fluid duration is 1801 s so it ends 1 s past the pinned block's start
        let fluid = TimeBlockModel(title: "Fluid", scheduledStart: start, duration: 1801)
        let pinned = TimeBlockModel(
            title: "Pinned",
            scheduledStart: start.addingTimeInterval(1800),
            duration: 1800,
            isPinned: true
        )

        let result = detector.detect(blocks: [fluid, pinned])

        #expect(result.count == 1)
        #expect(result[0].fluidBlockID == fluid.id)
        #expect(result[0].pinnedBlockID == pinned.id)
        // 1 second overlap truncates to 0 whole minutes
        #expect(result[0].overlapMinutes == 0)
    }

    // MARK: - Multiple Collisions (large shift)

    /// 10-block timeline alternating Fluid / Pinned.
    /// Two Fluid blocks have been shifted +90 min so each spills into its
    /// immediately following Pinned block by exactly 90 min.
    /// Asserts that detect() returns exactly 2 separate Collision entries,
    /// one per (Fluid, Pinned) pair, each with overlapMinutes == 90.
    @Test @MainActor func detect_multipleFluidsPastMultiplePinned_returnsOneCollisionEach() {
        let detector = CollisionDetector()
        let base = Date(timeIntervalSinceReferenceDate: 0) // fixed for determinism

        // Pair 1:
        // FluidA starts at base+0, duration = 5400+5400 = 10800 s
        //   → ends at base+10800
        // PinnedA starts at base+5400
        //   → overlap = 10800 - 5400 = 5400 s = 90 min ✓
        let fluidA = TimeBlockModel(
            title: "FluidA",
            scheduledStart: base,
            duration: 10_800   // 3 hr — ends 90 min past pinnedA
        )
        let pinnedA = TimeBlockModel(
            title: "PinnedA",
            scheduledStart: base.addingTimeInterval(5_400),  // 90 min after base
            duration: 1_800,
            isPinned: true
        )

        // Pair 2 — same geometry, offset 36 000 s (10 hr) so the pairs
        // never interact with each other or the fillers.
        let offset: TimeInterval = 36_000
        let fluidB = TimeBlockModel(
            title: "FluidB",
            scheduledStart: base.addingTimeInterval(offset),
            duration: 10_800
        )
        let pinnedB = TimeBlockModel(
            title: "PinnedB",
            scheduledStart: base.addingTimeInterval(offset + 5_400),
            duration: 1_800,
            isPinned: true
        )

        // 6 filler blocks (3 fluid, 3 pinned) with no overlaps.
        // Each fluid ends exactly at its paired pinned start (boundary = no collision).
        let fillerBase = base.addingTimeInterval(80_000)
        let fillers: [TimeBlockModel] = [
            TimeBlockModel(title: "F1", scheduledStart: fillerBase,                         duration: 600),
            TimeBlockModel(title: "P1", scheduledStart: fillerBase.addingTimeInterval(600),  duration: 600, isPinned: true),
            TimeBlockModel(title: "F2", scheduledStart: fillerBase.addingTimeInterval(2400), duration: 600),
            TimeBlockModel(title: "P2", scheduledStart: fillerBase.addingTimeInterval(3000), duration: 600, isPinned: true),
            TimeBlockModel(title: "F3", scheduledStart: fillerBase.addingTimeInterval(4800), duration: 600),
            TimeBlockModel(title: "P3", scheduledStart: fillerBase.addingTimeInterval(5400), duration: 600, isPinned: true),
        ]

        let allBlocks = [fluidA, pinnedA, fluidB, pinnedB] + fillers
        #expect(allBlocks.count == 10)

        let result = detector.detect(blocks: allBlocks)

        // Exactly 2 collisions — one per shifted Fluid block
        #expect(result.count == 2)

        let byFluid = Dictionary(grouping: result, by: \.fluidBlockID)

        // Collision from Fluid A
        let collisionA = byFluid[fluidA.id]
        #expect(collisionA?.count == 1)
        #expect(collisionA?.first?.pinnedBlockID == pinnedA.id)
        #expect(collisionA?.first?.overlapMinutes == 90)

        // Collision from Fluid B
        let collisionB = byFluid[fluidB.id]
        #expect(collisionB?.count == 1)
        #expect(collisionB?.first?.pinnedBlockID == pinnedB.id)
        #expect(collisionB?.first?.overlapMinutes == 90)
    }

    // MARK: - Sort Tie-Breaker

    /// A Fluid block and a Pinned block share the same scheduledStart.
    /// The Fluid block has non-zero duration so its end exceeds the shared
    /// start — this is a valid collision and must be reported regardless of
    /// input order.
    @Test @MainActor func detect_fluidAndPinnedSameStart_collisionDetected() {
        let detector = CollisionDetector()
        let start = Date()

        // Both blocks start at the same time; fluid ends 30 min later.
        let fluid = TimeBlockModel(title: "Fluid", scheduledStart: start, duration: 1800)
        let pinned = TimeBlockModel(title: "Pinned", scheduledStart: start, duration: 1800, isPinned: true)

        // Test both orderings to confirm the tie-breaker makes the result
        // independent of input order.
        let resultA = detector.detect(blocks: [fluid, pinned])
        let resultB = detector.detect(blocks: [pinned, fluid])

        #expect(resultA.count == 1)
        #expect(resultA[0].fluidBlockID == fluid.id)
        #expect(resultA[0].pinnedBlockID == pinned.id)
        #expect(resultA[0].overlapMinutes == 30)

        #expect(resultB.count == 1)
        #expect(resultB[0].fluidBlockID == fluid.id)
        #expect(resultB[0].pinnedBlockID == pinned.id)
        #expect(resultB[0].overlapMinutes == 30)
    }

    // MARK: - requiresReview Stamping
    /// non-colliding Fluid blocks (and all Pinned blocks) must have it false.
    @Test @MainActor func detect_stampsRequiresReview_onCollidingFluidBlocksOnly() {
        let detector = CollisionDetector()
        let start = Date()

        // clear — ends before pinned starts
        let safe = TimeBlockModel(title: "Safe", scheduledStart: start, duration: 600)
        // colliding — ends 30 min into pinned
        let colliding = TimeBlockModel(
            title: "Colliding",
            scheduledStart: start.addingTimeInterval(600),
            duration: 3600  // ends at start + 4200, pinned starts at start + 2400
        )
        let pinned = TimeBlockModel(
            title: "Pinned",
            scheduledStart: start.addingTimeInterval(2400),
            duration: 1800,
            isPinned: true
        )

        // Pre-condition: requiresReview starts false on all blocks
        #expect(safe.requiresReview == false)
        #expect(colliding.requiresReview == false)

        _ = detector.detect(blocks: [safe, colliding, pinned])

        // Colliding fluid block flagged
        #expect(colliding.requiresReview == true)
        // Non-colliding fluid block cleared
        #expect(safe.requiresReview == false)
        // Pinned block never touched
        #expect(pinned.requiresReview == false)
    }

    /// After a second pass where the collision is resolved, requiresReview
    /// must be cleared back to false (no stale flags left behind).
    @Test @MainActor func detect_clearsRequiresReview_whenCollisionResolved() {
        let detector = CollisionDetector()
        let start = Date()

        let fluid = TimeBlockModel(
            title: "Fluid",
            scheduledStart: start,
            duration: 3600  // initially overlaps pinned
        )
        let pinned = TimeBlockModel(
            title: "Pinned",
            scheduledStart: start.addingTimeInterval(1800),
            duration: 1800,
            isPinned: true
        )

        // First pass — collision exists, flag set
        _ = detector.detect(blocks: [fluid, pinned])
        #expect(fluid.requiresReview == true)

        // Resolve collision: shorten fluid so it ends exactly at pinned start
        fluid.duration = 1800

        // Second pass — no collision, flag must be cleared
        _ = detector.detect(blocks: [fluid, pinned])
        #expect(fluid.requiresReview == false)
    }
}
