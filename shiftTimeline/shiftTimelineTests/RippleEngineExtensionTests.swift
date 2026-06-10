import Engine
import Foundation
import Models
import Testing

// Live-mode `+x` semantics: the active block is already running, so `+x`
// extends its DURATION (the start is in the past and immutable), ripples
// downstream fluid blocks later by `x` up to the first pinned wall, squishes a
// trapped fluid run proportionally (respecting minimum durations), and rejects
// atomically — with a computable maximum — when the wall can't absorb it.
//
// Standard fixture used throughout (minutes from t0):
//   A(0–30, active) · F1(30–70, min 20) · F2(70–90, min 10) · P(90–120, pinned)
//   maximumExtension = (90 − 30) − (20 + 10) = 30 minutes.
@MainActor
struct RippleEngineExtensionTests {

    private let engine = RippleEngine()
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func date(atMinutes m: Double) -> Date { t0.addingTimeInterval(m * 60) }
    private func minutes(_ m: Double) -> TimeInterval { m * 60 }

    private func makeStandardTimeline() -> [TimeBlockModel] {
        [
            TimeBlockModel(
                title: "Active", scheduledStart: date(atMinutes: 0),
                duration: minutes(30), status: .active
            ),
            TimeBlockModel(
                title: "F1", scheduledStart: date(atMinutes: 30),
                duration: minutes(40), minimumDuration: minutes(20)
            ),
            TimeBlockModel(
                title: "F2", scheduledStart: date(atMinutes: 70),
                duration: minutes(20), minimumDuration: minutes(10)
            ),
            TimeBlockModel(
                title: "Pinned", scheduledStart: date(atMinutes: 90),
                duration: minutes(30), isPinned: true
            )
        ]
    }

    private func makeActive(durationMinutes: Double = 30) -> TimeBlockModel {
        TimeBlockModel(
            title: "Active", scheduledStart: date(atMinutes: 0),
            duration: minutes(durationMinutes), status: .active
        )
    }

    private func makePinned(atMinutes m: Double) -> TimeBlockModel {
        TimeBlockModel(
            title: "Pinned", scheduledStart: date(atMinutes: m),
            duration: minutes(30), isPinned: true
        )
    }

    // MARK: - Core extend semantics

    @Test func extendsActiveDurationNotStart() {
        let active = makeActive()
        let fluid = TimeBlockModel(title: "F", scheduledStart: date(atMinutes: 30), duration: minutes(30))

        let result = engine.applyExtension(
            blocks: [active, fluid],
            activeBlockID: active.id,
            delta: minutes(15)
        )

        #expect(result.status == .clean)
        #expect(active.scheduledStart == date(atMinutes: 0))
        #expect(active.duration == minutes(45))
        #expect(fluid.scheduledStart == date(atMinutes: 45))
        #expect(fluid.duration == minutes(30))
    }

    @Test func blocksPastPinnedWallDoNotMove() {
        let blocks = makeStandardTimeline()
        let after = TimeBlockModel(title: "AfterWall", scheduledStart: date(atMinutes: 120), duration: minutes(30))

        let result = engine.applyExtension(
            blocks: blocks + [after],
            activeBlockID: blocks[0].id,
            delta: minutes(10)
        )

        #expect(result.status != .exceedsAvailableSlack)
        #expect(blocks[3].scheduledStart == date(atMinutes: 90))   // pinned wall
        #expect(after.scheduledStart == date(atMinutes: 120))      // past the wall
    }

    // MARK: - Pinned immediately next (decision 1: a gap absorbs the extension)

    @Test func extensionIntoGapBeforePinnedIsAllowed() {
        let active = makeActive()
        let pinned = makePinned(atMinutes: 60)

        let result = engine.applyExtension(
            blocks: [active, pinned],
            activeBlockID: active.id,
            delta: minutes(15)
        )

        #expect(result.status == .clean)
        #expect(active.duration == minutes(45))
        #expect(pinned.scheduledStart == date(atMinutes: 60))
    }

    @Test func overrunOfImmediatePinnedIsRejectedAtomically() {
        let active = makeActive()
        let pinned = makePinned(atMinutes: 40)

        let result = engine.applyExtension(
            blocks: [active, pinned],
            activeBlockID: active.id,
            delta: minutes(15)
        )

        #expect(result.status == .exceedsAvailableSlack)
        #expect(active.duration == minutes(30))                    // untouched
        #expect(active.scheduledStart == date(atMinutes: 0))
        #expect(pinned.scheduledStart == date(atMinutes: 40))
    }

    // MARK: - Trapped fluid run (decision 3: proportional squish with minimums)

    @Test func trappedFluidRunIsSquishedProportionally() {
        let blocks = makeStandardTimeline()
        let (active, f1, f2, pinned) = (blocks[0], blocks[1], blocks[2], blocks[3])

        // +12: F1 shifts to 42; available before the wall = 90 − 42 = 48 < 60.
        // Proportional: F1 = 40/60 × 48 = 32, F2 = 20/60 × 48 = 16.
        let result = engine.applyExtension(
            blocks: blocks,
            activeBlockID: active.id,
            delta: minutes(12)
        )

        #expect(result.status == .hasCollisions)
        #expect(active.duration == minutes(42))
        #expect(f1.scheduledStart == date(atMinutes: 42))
        #expect(f1.duration == minutes(32))
        #expect(f2.scheduledStart == date(atMinutes: 74))
        #expect(f2.duration == minutes(16))
        // The run ends exactly at the wall.
        #expect(f2.scheduledStart.addingTimeInterval(f2.duration) == pinned.scheduledStart)
        #expect(result.compressedBlockIDs.contains(f1.id))
        #expect(result.compressedBlockIDs.contains(f2.id))
    }

    @Test func extensionEqualToMaximumCompressesRunToMinimums() {
        let blocks = makeStandardTimeline()
        let (active, f1, f2, _) = (blocks[0], blocks[1], blocks[2], blocks[3])

        let result = engine.applyExtension(
            blocks: blocks,
            activeBlockID: active.id,
            delta: minutes(30)
        )

        #expect(result.status == .hasCollisions)
        #expect(active.duration == minutes(60))
        #expect(f1.scheduledStart == date(atMinutes: 60))
        #expect(f1.duration == minutes(20))                        // at minimum
        #expect(f2.scheduledStart == date(atMinutes: 80))
        #expect(f2.duration == minutes(10))                        // at minimum
    }

    @Test func extensionBeyondMaximumIsRejectedAtomically() {
        let blocks = makeStandardTimeline()
        let (active, f1, f2, pinned) = (blocks[0], blocks[1], blocks[2], blocks[3])

        let result = engine.applyExtension(
            blocks: blocks,
            activeBlockID: active.id,
            delta: minutes(31)
        )

        #expect(result.status == .exceedsAvailableSlack)
        // Nothing mutated — the reject happens before any propagation.
        #expect(active.duration == minutes(30))
        #expect(f1.scheduledStart == date(atMinutes: 30))
        #expect(f1.duration == minutes(40))
        #expect(f2.scheduledStart == date(atMinutes: 70))
        #expect(f2.duration == minutes(20))
        #expect(pinned.scheduledStart == date(atMinutes: 90))
    }

    // MARK: - maximumExtension (decision 2: computable for the user)

    @Test func maximumExtensionIsNilWithoutDownstreamWall() {
        let active = makeActive()
        let fluid = TimeBlockModel(title: "F", scheduledStart: date(atMinutes: 30), duration: minutes(30))

        let max = engine.maximumExtension(blocks: [active, fluid], activeBlockID: active.id)

        #expect(max == nil)
    }

    @Test func maximumExtensionWithImmediatePinnedIsTheGap() {
        let active = makeActive()
        let pinned = makePinned(atMinutes: 60)

        let max = engine.maximumExtension(blocks: [active, pinned], activeBlockID: active.id)

        #expect(max == minutes(30))
    }

    @Test func maximumExtensionWithTrappedRunAccountsForMinimums() {
        let blocks = makeStandardTimeline()

        let max = engine.maximumExtension(blocks: blocks, activeBlockID: blocks[0].id)

        // (wall 90 − F1 start 30) − (min 20 + min 10) = 30 minutes.
        #expect(max == minutes(30))
    }

    @Test func maximumExtensionIsClampedAtZeroWhenAlreadyTight() {
        let active = makeActive(durationMinutes: 40)
        let pinned = makePinned(atMinutes: 30)

        let max = engine.maximumExtension(blocks: [active, pinned], activeBlockID: active.id)

        #expect(max == 0)
    }

    // MARK: - Pinned active block (a pin anchors the start, not the duration)

    @Test func pinnedActiveBlockCanStillExtend() {
        let active = TimeBlockModel(
            title: "Ceremony", scheduledStart: date(atMinutes: 0), duration: minutes(30),
            isPinned: true, status: .active
        )
        let fluid = TimeBlockModel(title: "F", scheduledStart: date(atMinutes: 30), duration: minutes(30))

        let result = engine.applyExtension(
            blocks: [active, fluid],
            activeBlockID: active.id,
            delta: minutes(10)
        )

        #expect(result.status == .clean)
        #expect(active.scheduledStart == date(atMinutes: 0))
        #expect(active.duration == minutes(40))
        #expect(fluid.scheduledStart == date(atMinutes: 40))
    }

    // MARK: - No-ops

    @Test func zeroDeltaIsNoOp() {
        let blocks = makeStandardTimeline()

        let result = engine.applyExtension(blocks: blocks, activeBlockID: blocks[0].id, delta: 0)

        #expect(result.status == .clean)
        #expect(blocks[0].duration == minutes(30))
        #expect(blocks[1].scheduledStart == date(atMinutes: 30))
    }

    @Test func unknownActiveBlockIDIsNoOp() {
        let blocks = makeStandardTimeline()

        let result = engine.applyExtension(blocks: blocks, activeBlockID: UUID(), delta: minutes(10))

        #expect(result.status == .clean)
        #expect(blocks[0].duration == minutes(30))
    }

    @Test func negativeDeltaIsNoOp() {
        let blocks = makeStandardTimeline()

        let result = engine.applyExtension(blocks: blocks, activeBlockID: blocks[0].id, delta: minutes(-10))

        #expect(result.status == .clean)
        #expect(blocks[0].duration == minutes(30))
        #expect(blocks[1].scheduledStart == date(atMinutes: 30))
    }
}

// MARK: - Extension preview (decision 4: the confirm sheet must match the commit)

@MainActor
struct ShiftPreviewGeneratorExtensionTests {

    private let engine = RippleEngine()
    private let generator = ShiftPreviewGenerator()
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func date(atMinutes m: Double) -> Date { t0.addingTimeInterval(m * 60) }
    private func minutes(_ m: Double) -> TimeInterval { m * 60 }

    private func makeStandardTimeline() -> [TimeBlockModel] {
        [
            TimeBlockModel(
                title: "Active", scheduledStart: date(atMinutes: 0),
                duration: minutes(30), status: .active
            ),
            TimeBlockModel(
                title: "F1", scheduledStart: date(atMinutes: 30),
                duration: minutes(40), minimumDuration: minutes(20)
            ),
            TimeBlockModel(
                title: "F2", scheduledStart: date(atMinutes: 70),
                duration: minutes(20), minimumDuration: minutes(10)
            ),
            TimeBlockModel(
                title: "Pinned", scheduledStart: date(atMinutes: 90),
                duration: minutes(30), isPinned: true
            )
        ]
    }

    @Test func previewDoesNotMutateOriginals() {
        let blocks = makeStandardTimeline()

        _ = generator.generateExtensionPreview(blocks: blocks, activeBlockID: blocks[0].id, delta: minutes(12))

        #expect(blocks[0].duration == minutes(30))
        #expect(blocks[1].scheduledStart == date(atMinutes: 30))
        #expect(blocks[1].duration == minutes(40))
        #expect(blocks[2].scheduledStart == date(atMinutes: 70))
    }

    @Test func previewProjectsTheSameTimelineTheCommitProduces() {
        let previewBlocks = makeStandardTimeline()
        let commitBlocks = makeStandardTimeline()

        let preview = generator.generateExtensionPreview(
            blocks: previewBlocks,
            activeBlockID: previewBlocks[0].id,
            delta: minutes(12)
        )
        let committed = engine.applyExtension(
            blocks: commitBlocks,
            activeBlockID: commitBlocks[0].id,
            delta: minutes(12)
        )

        #expect(preview.status == committed.status)
        for (projected, live) in zip(preview.previewBlocks, committed.blocks) {
            #expect(projected.title == live.title)
            #expect(projected.scheduledStart == live.scheduledStart)
            #expect(projected.duration == live.duration)
        }
    }

    @Test func previewBeyondMaximumReportsSlackAndMovesNothing() {
        let blocks = makeStandardTimeline()

        let preview = generator.generateExtensionPreview(
            blocks: blocks,
            activeBlockID: blocks[0].id,
            delta: minutes(31)
        )

        #expect(preview.status == .exceedsAvailableSlack)
        #expect(preview.maximumExtension == minutes(30))
        #expect(preview.diffs.values.allSatisfy { $0 == 0 })
    }

    @Test func previewWithinSlackCarriesMaximumForContext() {
        let blocks = makeStandardTimeline()

        let preview = generator.generateExtensionPreview(
            blocks: blocks,
            activeBlockID: blocks[0].id,
            delta: minutes(10)
        )

        #expect(preview.status != .exceedsAvailableSlack)
        #expect(preview.maximumExtension == minutes(30))
    }
}
