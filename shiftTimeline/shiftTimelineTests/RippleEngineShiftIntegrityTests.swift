import Engine
import Foundation
import Models
import Testing

/// Shift-integrity suite: the committed timeline must match what the engine
/// promises, deterministically.
///
/// Covers the two live-shift defects:
/// 1. **Same-start ties** — blocks sharing a `scheduledStart` must ripple
///    *together* regardless of their (previously ambiguous) sort order, in both
///    `recalculate` and `generatePreview`.
/// 2. **Commit pipeline** — `applyShift` runs the full four stages (shift →
///    collide → compress) so a committed shift matches the confirmed preview:
///    blocks squeezed into a pinned wall are compressed to fit, never left
///    overlapping; stale `requiresReview` flags are cleared on clean shifts.
@MainActor
struct RippleEngineShiftIntegrityTests {

    private let engine = RippleEngine()
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func fluid(
        _ title: String,
        startOffset: TimeInterval,
        duration: TimeInterval = 1800,
        minimum: TimeInterval = 600,
        requiresReview: Bool = false
    ) -> TimeBlockModel {
        TimeBlockModel(
            title: title,
            scheduledStart: t0.addingTimeInterval(startOffset),
            originalStart: t0.addingTimeInterval(startOffset),
            duration: duration,
            minimumDuration: minimum,
            isPinned: false,
            requiresReview: requiresReview
        )
    }

    private func pinned(_ title: String, startOffset: TimeInterval, duration: TimeInterval = 1800) -> TimeBlockModel {
        TimeBlockModel(
            title: title,
            scheduledStart: t0.addingTimeInterval(startOffset),
            originalStart: t0.addingTimeInterval(startOffset),
            duration: duration,
            isPinned: true
        )
    }

    // MARK: - Same-start ties (recalculate)

    @Test func sameStartSiblingShiftsWithChangedBlock() {
        // A and B start at the same instant (parallel tracks); C follows.
        let a = fluid("A", startOffset: 0)
        let b = fluid("B", startOffset: 0)
        let c = fluid("C", startOffset: 1800)

        let result = engine.recalculate(blocks: [a, b, c], changedBlockID: a.id, delta: 600)

        #expect(result.status == .clean)
        #expect(a.scheduledStart == t0.addingTimeInterval(600))
        #expect(b.scheduledStart == t0.addingTimeInterval(600))   // sibling moves too
        #expect(c.scheduledStart == t0.addingTimeInterval(2400))
    }

    @Test func sameStartSiblingShiftsRegardlessOfWhichSiblingChanges() {
        // The mirror case: shifting B must drag A along identically. With the
        // old index-based shift set, whichever sibling happened to sort first
        // was silently excluded — nondeterministic by UUID.
        let a = fluid("A", startOffset: 0)
        let b = fluid("B", startOffset: 0)

        let result = engine.recalculate(blocks: [a, b], changedBlockID: b.id, delta: 600)

        #expect(result.status == .clean)
        #expect(a.scheduledStart == t0.addingTimeInterval(600))
        #expect(b.scheduledStart == t0.addingTimeInterval(600))
    }

    @Test func sameStartTieIsDeterministicAcrossRebuilds() {
        // Fresh UUIDs each run — every fluid block at/after the changed block's
        // start must move by exactly delta, run after run.
        for _ in 0..<5 {
            let x = fluid("X", startOffset: 0)
            let y = fluid("Y", startOffset: 0)
            let z = fluid("Z", startOffset: 3600)
            _ = engine.recalculate(blocks: [x, y, z], changedBlockID: x.id, delta: 900)
            #expect(x.scheduledStart == t0.addingTimeInterval(900))
            #expect(y.scheduledStart == t0.addingTimeInterval(900))
            #expect(z.scheduledStart == t0.addingTimeInterval(4500))
        }
    }

    @Test func sameStartPinnedSiblingNeverMoves() {
        let a = fluid("A", startOffset: 0)
        let p = pinned("P", startOffset: 0)

        let result = engine.recalculate(blocks: [a, p], changedBlockID: a.id, delta: 600)

        #expect(result.status == .clean)
        #expect(a.scheduledStart == t0.addingTimeInterval(600))
        #expect(p.scheduledStart == t0) // pinned anchored
    }

    @Test func fluidAtPinnedWallInstantShiftsButBlocksPastWallDoNot() {
        // W starts at exactly the wall's instant. Canonical order puts Fluid
        // before Pinned on a tie, so W sits *at* the wall (shiftable); Z sits
        // *past* it (halted).
        let a = fluid("A", startOffset: 0)
        let wall = pinned("Wall", startOffset: 3600)
        let w = fluid("W", startOffset: 3600)
        let z = fluid("Z", startOffset: 7200)

        _ = engine.recalculate(blocks: [a, wall, w, z], changedBlockID: a.id, delta: 600)

        #expect(w.scheduledStart == t0.addingTimeInterval(4200))  // at the wall → shifts
        #expect(z.scheduledStart == t0.addingTimeInterval(7200))  // past the wall → halted
        #expect(wall.scheduledStart == t0.addingTimeInterval(3600))
    }

    // MARK: - Same-start ties (preview parity)

    @Test func previewIncludesSameStartSibling() {
        let a = fluid("A", startOffset: 0)
        let b = fluid("B", startOffset: 0)
        let c = fluid("C", startOffset: 1800)

        let preview = ShiftPreviewGenerator().generatePreview(blocks: [a, b, c], blockID: a.id, delta: 600)

        #expect(preview.diffs[a.id] == 600)
        #expect(preview.diffs[b.id] == 600)   // sibling previewed as moving
        #expect(preview.diffs[c.id] == 600)
        // Preview never mutates the live models.
        #expect(a.scheduledStart == t0)
        #expect(b.scheduledStart == t0)
    }

    // MARK: - applyShift: the full commit pipeline

    @Test func applyShiftCompressesBlocksSqueezedIntoPinnedWall() {
        // A(30m) + B(30m) with a pinned wall 75m out. Shifting A +30m squeezes
        // 60m of content into the 45m gap before the wall → proportional
        // compression (22.5m each), laid out contiguously, ending exactly at
        // the wall. This is what the preview shows — commit must match it.
        let a = fluid("A", startOffset: 0, duration: 1800)
        let b = fluid("B", startOffset: 1800, duration: 1800)
        let wall = pinned("Wall", startOffset: 4500)

        let result = engine.applyShift(blocks: [a, b, wall], changedBlockID: a.id, delta: 1800)

        #expect(result.status == .hasCollisions)
        #expect(a.scheduledStart == t0.addingTimeInterval(1800))
        #expect(a.duration == 1350)                                 // 22.5m
        #expect(b.scheduledStart == t0.addingTimeInterval(3150))    // contiguous after A
        #expect(b.duration == 1350)
        // The trapped run ends exactly at the wall — no overlap survives.
        #expect(b.scheduledStart.addingTimeInterval(b.duration) == wall.scheduledStart)
        #expect(result.compressedBlockIDs.contains(a.id))
        #expect(result.compressedBlockIDs.contains(b.id))
        #expect(wall.scheduledStart == t0.addingTimeInterval(4500))
        #expect(wall.duration == 1800)
    }

    @Test func applyShiftReportsImpossibleWhenMinimumsExceedGap() {
        // A(45m) + B(45m) before a wall at 90m. Shifting +45m leaves a 45m gap
        // (A's new start → wall) but the minimums total 60m — impossible. The
        // trapped run is parked at minimum durations from the gap start and
        // flagged for review.
        let a = fluid("A", startOffset: 0, duration: 2700, minimum: 1800)
        let b = fluid("B", startOffset: 2700, duration: 2700, minimum: 1800)
        let wall = pinned("Wall", startOffset: 5400)

        let result = engine.applyShift(blocks: [a, b, wall], changedBlockID: a.id, delta: 2700)

        #expect(result.status == .impossible)
        #expect(a.scheduledStart == t0.addingTimeInterval(2700))
        #expect(a.duration == 1800)                               // parked at minimum
        #expect(b.scheduledStart == t0.addingTimeInterval(4500))  // contiguous after A
        #expect(b.duration == 1800)
        #expect(a.requiresReview)
        #expect(b.requiresReview)
        #expect(wall.scheduledStart == t0.addingTimeInterval(5400)) // wall anchored
    }

    @Test func applyShiftWithoutCollisionsStaysCleanAndClearsStaleReviewFlags() {
        // A stale requiresReview flag from an earlier (resolved) collision must
        // be cleared by the commit pipeline's detection pass.
        let a = fluid("A", startOffset: 0, requiresReview: true)
        let b = fluid("B", startOffset: 1800, requiresReview: true)

        let result = engine.applyShift(blocks: [a, b], changedBlockID: a.id, delta: 600)

        #expect(result.status == .clean)
        #expect(result.collisions.isEmpty)
        #expect(result.compressedBlockIDs.isEmpty)
        #expect(!a.requiresReview)
        #expect(!b.requiresReview)
        #expect(a.duration == 1800)   // durations untouched on a clean shift
        #expect(b.duration == 1800)
    }

    @Test func applyShiftRefusesToShiftPinnedBlock() {
        let p = pinned("P", startOffset: 0)
        let b = fluid("B", startOffset: 3600)

        let result = engine.applyShift(blocks: [p, b], changedBlockID: p.id, delta: 600)

        #expect(result.status == .pinnedBlockCannotShift)
        #expect(p.scheduledStart == t0)
        #expect(b.scheduledStart == t0.addingTimeInterval(3600))
    }
}
