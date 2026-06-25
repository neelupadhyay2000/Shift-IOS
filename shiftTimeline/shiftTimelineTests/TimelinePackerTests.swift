import Engine
import Foundation
import Models
import Testing

/// Locks the behaviour of `TimelinePacker` — the pure cursor-walk extracted from
/// `TimelineBuilderView.applyReorder` / `recalculateStartTimesAfterDelete`. These
/// assertions encode the exact pre-extraction behaviour so the refactor is proven
/// non-functional.
@MainActor
struct TimelinePackerTests {

    private let packer = TimelinePacker()
    private let base = Date(timeIntervalSinceReferenceDate: 0)

    private func at(_ minutes: Double) -> Date { base.addingTimeInterval(minutes * 60) }

    // MARK: - Fluid packing

    @Test func packsFluidRunContiguouslyFromOrigin() {
        let a = TimeBlockModel(title: "A", scheduledStart: at(99), duration: 600)   // 10m
        let b = TimeBlockModel(title: "B", scheduledStart: at(99), duration: 1800)  // 30m
        let c = TimeBlockModel(title: "C", scheduledStart: at(99), duration: 900)   // 15m

        packer.pack([a, b, c], origin: at(0))

        #expect(a.scheduledStart == at(0))
        #expect(b.scheduledStart == at(10))
        #expect(c.scheduledStart == at(40))
    }

    @Test func emptyInputIsNoOp() {
        packer.pack([], origin: at(0))   // must not crash
    }

    // MARK: - Pinned anchoring

    @Test func pinnedBlockStaysFixedAndAnchorsTheRun() {
        // Fluid (10m) → Pinned at 60m (30m) → Fluid (15m). The first fluid packs
        // at origin; the pinned keeps its clock time and pushes the cursor to its
        // end; the trailing fluid resumes there.
        let a = TimeBlockModel(title: "A", scheduledStart: at(5), duration: 600)
        let pinned = TimeBlockModel(title: "P", scheduledStart: at(60), duration: 1800, isPinned: true)
        let c = TimeBlockModel(title: "C", scheduledStart: at(5), duration: 900)

        packer.pack([a, pinned, c], origin: at(0))

        #expect(a.scheduledStart == at(0))
        #expect(pinned.scheduledStart == at(60))   // unchanged
        #expect(c.scheduledStart == at(90))        // resumes at pinned end (60 + 30)
    }

    @Test func leadingPinnedIgnoresOriginAndAnchorsTheWalk() {
        let pinned = TimeBlockModel(title: "P", scheduledStart: at(120), duration: 1800, isPinned: true)
        let b = TimeBlockModel(title: "B", scheduledStart: at(0), duration: 600)

        // origin far before the pinned block: the leading pinned anchors the walk.
        packer.pack([pinned, b], origin: at(0))

        #expect(pinned.scheduledStart == at(120))
        #expect(b.scheduledStart == at(150))   // 120 + 30
    }

    // MARK: - Delete-path flags

    @Test func syncOriginalStartUpdatesOriginalStartForFluidOnly() {
        let a = TimeBlockModel(title: "A", scheduledStart: at(99), originalStart: at(99), duration: 600)
        let pinned = TimeBlockModel(title: "P", scheduledStart: at(60), originalStart: at(60), duration: 1800, isPinned: true)

        packer.pack([a, pinned], origin: at(0), syncOriginalStart: true)

        #expect(a.originalStart == at(0))          // synced to new fluid start
        #expect(pinned.originalStart == at(60))    // pinned untouched
    }

    @Test func clearRequiresReviewClearsFluidOnly() {
        let a = TimeBlockModel(title: "A", scheduledStart: at(0), duration: 600, requiresReview: true)
        let pinned = TimeBlockModel(title: "P", scheduledStart: at(60), duration: 600, isPinned: true, requiresReview: true)

        packer.pack([a, pinned], origin: at(0), clearRequiresReview: true)

        #expect(a.requiresReview == false)
        #expect(pinned.requiresReview == true)     // pinned untouched
    }

    @Test func defaultsLeaveOriginalStartAndReviewFlagUntouched() {
        let a = TimeBlockModel(title: "A", scheduledStart: at(99), originalStart: at(99), duration: 600, requiresReview: true)

        packer.pack([a], origin: at(0))

        #expect(a.scheduledStart == at(0))
        #expect(a.originalStart == at(99))   // not synced by default (reorder path)
        #expect(a.requiresReview == true)    // not cleared by default (reorder path)
    }

    // MARK: - Reorder-init equivalence

    /// The reorder path computes `origin = min(scheduledStart)`. With a leading
    /// pinned block whose start is later than that minimum, the packer must still
    /// produce the same result as the old unconditional `cursor = anchor` init —
    /// because a pinned block's end always dominates the earlier anchor.
    @Test func reorderMinOriginMatchesLegacyAnchorInitWithLeadingPinned() {
        let pinned = TimeBlockModel(title: "P", scheduledStart: at(60), duration: 1800, isPinned: true)
        let b = TimeBlockModel(title: "B", scheduledStart: at(20), duration: 600)
        let blocks = [pinned, b]

        let anchor = blocks.map(\.scheduledStart).min() ?? at(0)   // = 20m
        packer.pack(blocks, origin: anchor)

        #expect(pinned.scheduledStart == at(60))
        #expect(b.scheduledStart == at(90))   // 60 + 30, identical to legacy walk
    }
}
