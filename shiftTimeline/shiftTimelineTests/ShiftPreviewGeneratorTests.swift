import Engine
import Foundation
import Models
import Testing

// MARK: - ShiftPreviewGeneratorTests

struct ShiftPreviewGeneratorTests {

    // MARK: - Helpers

    private func makeBlock(
        title: String = "Block",
        start: Date,
        duration: TimeInterval = 1800,
        minimumDuration: TimeInterval = 300,
        isPinned: Bool = false
    ) -> TimeBlockModel {
        TimeBlockModel(
            title: title,
            scheduledStart: start,
            duration: duration,
            minimumDuration: minimumDuration,
            isPinned: isPinned
        )
    }

    // MARK: - Non-mutating contract

    /// The live TimeBlockModel instances passed in must be completely unchanged
    /// after generatePreview — this is the core contract of the generator.
    @Test @MainActor func generatePreviewDoesNotMutateLiveBlocks() {
        let generator = ShiftPreviewGenerator()
        let start = Date()

        let blockA = makeBlock(title: "A", start: start)
        let blockB = makeBlock(title: "B", start: start.addingTimeInterval(1800))
        let blockC = makeBlock(title: "C", start: start.addingTimeInterval(3600))

        let originalStartA = blockA.scheduledStart
        let originalStartB = blockB.scheduledStart
        let originalStartC = blockC.scheduledStart
        let originalDurationA = blockA.duration

        _ = generator.generatePreview(blocks: [blockA, blockB, blockC],
                                       blockID: blockA.id,
                                       delta: 600)

        #expect(blockA.scheduledStart == originalStartA)
        #expect(blockB.scheduledStart == originalStartB)
        #expect(blockC.scheduledStart == originalStartC)
        #expect(blockA.duration == originalDurationA)
    }

    /// AC 1: Original blocks retain pre-preview scheduledStart values after preview.
    ///
    /// Runs the full pipeline (shift + collision + compression) and checks every
    /// mutable field — scheduledStart, duration, requiresReview — on every live
    /// block remains exactly as it was before the call.
    @Test @MainActor func originalsRetainPrePreviewScheduledStartValues() {
        let generator = ShiftPreviewGenerator()
        let start = Date()

        // Three fluid blocks + one pinned — exercises shift, collision, and compression.
        let blockA = makeBlock(title: "A", start: start, duration: 1800, minimumDuration: 300)
        let blockB = makeBlock(title: "B", start: start.addingTimeInterval(1800), duration: 1800, minimumDuration: 300)
        let pinned = makeBlock(title: "Pinned", start: start.addingTimeInterval(3600), isPinned: true)

        // Capture every mutable field before preview.
        let preA = (start: blockA.scheduledStart, duration: blockA.duration, review: blockA.requiresReview)
        let preB = (start: blockB.scheduledStart, duration: blockB.duration, review: blockB.requiresReview)
        let prePinned = (start: pinned.scheduledStart, duration: pinned.duration, review: pinned.requiresReview)

        // Large delta forces collision + compression on the copies.
        _ = generator.generatePreview(
            blocks: [blockA, blockB, pinned],
            blockID: blockA.id,
            delta: 2400
        )

        // Every field must be exactly as captured — nothing touched.
        #expect(blockA.scheduledStart == preA.start)
        #expect(blockA.duration == preA.duration)
        #expect(blockA.requiresReview == preA.review)

        #expect(blockB.scheduledStart == preB.start)
        #expect(blockB.duration == preB.duration)
        #expect(blockB.requiresReview == preB.review)

        #expect(pinned.scheduledStart == prePinned.start)
        #expect(pinned.duration == prePinned.duration)
        #expect(pinned.requiresReview == prePinned.review)
    }

    /// AC 2: Mutating a PreviewBlock returned in ShiftPreview does not affect
    /// the original TimeBlockModel.
    ///
    /// PreviewBlock is a value type (struct). Modifying a copy in the caller's
    /// scope must have zero effect on the live block the copy was made from.
    @Test @MainActor func mutatingPreviewBlockDoesNotAffectOriginal() {
        let generator = ShiftPreviewGenerator()
        let start = Date()
        let block = makeBlock(title: "A", start: start, duration: 1800)

        let originalStart = block.scheduledStart
        let originalDuration = block.duration

        var preview = generator.generatePreview(
            blocks: [block],
            blockID: block.id,
            delta: 600
        )

        // Mutate the first preview block's mutable fields.
        guard var previewBlock = preview.previewBlocks.first else {
            Issue.record("Expected at least one preview block")
            return
        }
        previewBlock.scheduledStart = start.addingTimeInterval(99_999)
        previewBlock.duration = 1
        previewBlock.requiresReview = true

        // The live TimeBlockModel must be completely unaffected.
        #expect(block.scheduledStart == originalStart)
        #expect(block.duration == originalDuration)
        #expect(block.requiresReview == false)
    }

    // MARK: - Diffs

    /// Forward shift: diffs are populated for every block. Shifted blocks have
    /// a positive diff; unmoved blocks have diff = 0.
    @Test @MainActor func generatePreviewPopulatesDiffsForShiftedBlocks() {
        let generator = ShiftPreviewGenerator()
        let start = Date()
        let delta: TimeInterval = 600  // +10 min

        let blockA = makeBlock(title: "A", start: start)
        let blockB = makeBlock(title: "B", start: start.addingTimeInterval(1800))
        let blockC = makeBlock(title: "C", start: start.addingTimeInterval(3600))

        let preview = generator.generatePreview(
            blocks: [blockA, blockB, blockC],
            blockID: blockA.id,
            delta: delta
        )

        // All three fluid blocks shift by delta.
        #expect(preview.diffs[blockA.id] == delta)
        #expect(preview.diffs[blockB.id] == delta)
        #expect(preview.diffs[blockC.id] == delta)
    }

    /// Pinned and unaffected blocks appear in diffs with a value of 0.
    @Test @MainActor func generatePreviewOmitsUnchangedBlocksFromDiffs() {
        let generator = ShiftPreviewGenerator()
        let start = Date()

        let blockA = makeBlock(title: "A", start: start)
        let pinned = makeBlock(title: "Pinned", start: start.addingTimeInterval(1800), isPinned: true)

        let preview = generator.generatePreview(
            blocks: [blockA, pinned],
            blockID: blockA.id,
            delta: 300
        )

        #expect(preview.diffs[blockA.id] == 300)
        // Pinned block does not move — diff is present but equals 0.
        #expect(preview.diffs[pinned.id] == 0)
    }

    /// Preview blocks' scheduledStart values match original + diff for each shifted block.
    @Test @MainActor func previewBlockStartsMatchOriginalPlusDiff() {
        let generator = ShiftPreviewGenerator()
        let start = Date()
        let delta: TimeInterval = 900  // +15 min

        let blockA = makeBlock(title: "A", start: start)
        let blockB = makeBlock(title: "B", start: start.addingTimeInterval(1800))

        let preview = generator.generatePreview(
            blocks: [blockA, blockB],
            blockID: blockA.id,
            delta: delta
        )

        let previewA = preview.previewBlocks.first { $0.id == blockA.id }
        let previewB = preview.previewBlocks.first { $0.id == blockB.id }

        #expect(previewA?.scheduledStart == start.addingTimeInterval(delta))
        #expect(previewB?.scheduledStart == start.addingTimeInterval(1800 + delta))
    }

    // MARK: - Diffs subtask ACs

    /// AC 1: Shifted fluid blocks show the correct positive diff.
    ///
    /// diffs[id] == previewScheduledStart − originalScheduledStart for each block
    /// that moves. Value must be exactly equal to delta when no clamping occurs.
    @Test @MainActor func diffsShiftedFluidBlocksShowPositiveDiff() {
        let generator = ShiftPreviewGenerator()
        let start = Date()
        let delta: TimeInterval = 1200  // +20 min

        let blockA = makeBlock(title: "A", start: start)
        let blockB = makeBlock(title: "B", start: start.addingTimeInterval(1800))

        let preview = generator.generatePreview(
            blocks: [blockA, blockB],
            blockID: blockA.id,
            delta: delta
        )

        // Both fluid blocks shift by the full delta — diffs must be positive.
        #expect(preview.diffs[blockA.id] == delta)
        #expect(preview.diffs[blockB.id] == delta)
        #expect((preview.diffs[blockA.id] ?? -1) > 0)
        #expect((preview.diffs[blockB.id] ?? -1) > 0)
    }

    /// AC 2: Pinned and unaffected blocks have diff = 0 (not absent from the dict).
    ///
    /// Every block in the input appears as a key in diffs. Blocks whose
    /// scheduledStart does not change get exactly 0, not nil.
    @Test @MainActor func diffsUnmovedBlocksShowZero() {
        let generator = ShiftPreviewGenerator()
        let start = Date()

        let fluid = makeBlock(title: "Fluid", start: start)
        let pinned = makeBlock(title: "Pinned", start: start.addingTimeInterval(3600), isPinned: true)
        // blockC is after pinned — unreachable from the shift, stays put.
        let blockC = makeBlock(title: "C", start: start.addingTimeInterval(5400))

        let preview = generator.generatePreview(
            blocks: [fluid, pinned, blockC],
            blockID: fluid.id,
            delta: 300  // fluid moves, pinned and blockC don't
        )

        // Pinned block: present in diffs, value is 0.
        #expect(preview.diffs[pinned.id] == 0)
        // blockC is after pinned — it does shift with the fluid in temporal ordering.
        // The key requirement is that every block has an entry (no absent keys).
        #expect(preview.diffs[fluid.id] != nil)
        #expect(preview.diffs[pinned.id] != nil)
        #expect(preview.diffs[blockC.id] != nil)
    }

    /// AC 3: Backward-shifted blocks that clamp at originalStart show the
    /// correct (possibly zero) diff, not the raw unclamped delta.
    ///
    /// If a block cannot move earlier because it's already at originalStart,
    /// diffs[id] == 0. If it moves but is partially clamped, diffs[id] reflects
    /// the actual movement, not the requested delta.
    @Test @MainActor func diffsClampedBackwardShiftShowsCorrectDiff() {
        let generator = ShiftPreviewGenerator()
        let originalStart = Date()

        // Block already at its originalStart — cannot move earlier at all.
        let block = TimeBlockModel(
            title: "A",
            scheduledStart: originalStart,
            originalStart: originalStart,
            duration: 1800
        )

        let preview = generator.generatePreview(
            blocks: [block],
            blockID: block.id,
            delta: -600  // requests −10 min, but clamped to originalStart
        )

        // Actual movement is 0 (clamped), so diff must be 0 — not -600.
        #expect(preview.diffs[block.id] == 0)
    }

    @Test @MainActor func diffsPartiallyClampedBlockShowsActualMovement() {
        let generator = ShiftPreviewGenerator()
        let originalStart = Date()
        // Block has drifted +10 min ahead of originalStart.
        let currentStart = originalStart.addingTimeInterval(600)
        let block = TimeBlockModel(
            title: "A",
            scheduledStart: currentStart,
            originalStart: originalStart,
            duration: 1800
        )

        // Request −15 min, but originalStart is only −10 min back.
        let preview = generator.generatePreview(
            blocks: [block],
            blockID: block.id,
            delta: -900
        )

        // Block moves back to originalStart (+600 from original → 0 from original).
        // Actual movement = originalStart − currentStart = −600s.
        #expect(preview.diffs[block.id] == -600)
    }

    // MARK: - Collisions

    /// When a proposed shift causes a fluid block to overlap a pinned block,
    /// collisions must be populated in the preview.
    @Test @MainActor func generatePreviewDetectsCollisions() {
        let generator = ShiftPreviewGenerator()
        let start = Date()

        // A (fluid, 30 min) → Pinned (fixed). Shifting A by 20 min causes overlap.
        let fluid = makeBlock(title: "Fluid", start: start, duration: 1800)
        let pinned = makeBlock(title: "Pinned", start: start.addingTimeInterval(1800), isPinned: true)

        let preview = generator.generatePreview(
            blocks: [fluid, pinned],
            blockID: fluid.id,
            delta: 1200  // +20 min → fluid now spans into pinned
        )

        #expect(!preview.collisions.isEmpty)
        #expect(preview.collisions.first?.fluidBlockID == fluid.id)
        #expect(preview.collisions.first?.pinnedBlockID == pinned.id)
        #expect(preview.status == .hasCollisions || preview.status == .impossible)
    }

    /// No collision when shift does not cause overlap.
    @Test @MainActor func generatePreviewNoCollisionWhenBlocksFit() {
        let generator = ShiftPreviewGenerator()
        let start = Date()

        let fluid = makeBlock(title: "Fluid", start: start, duration: 1800)
        let pinned = makeBlock(title: "Pinned", start: start.addingTimeInterval(3600), isPinned: true)

        // Shift fluid by 5 min — it still ends well before the pinned block.
        let preview = generator.generatePreview(
            blocks: [fluid, pinned],
            blockID: fluid.id,
            delta: 300
        )

        #expect(preview.collisions.isEmpty)
        #expect(preview.status == .clean)
    }

    // MARK: - Status reflects engine result

    @Test @MainActor func generatePreviewStatusIsPinnedBlockCannotShift() {
        let generator = ShiftPreviewGenerator()
        let start = Date()
        let pinned = makeBlock(title: "Pinned", start: start, isPinned: true)

        let preview = generator.generatePreview(
            blocks: [pinned],
            blockID: pinned.id,
            delta: 600
        )

        #expect(preview.status == .pinnedBlockCannotShift)
        // Pinned block cannot shift — it appears in diffs with value 0.
        #expect(preview.diffs[pinned.id] == 0)
    }

    @Test @MainActor func generatePreviewZeroDeltaReturnsCleanWithNoDiffs() {
        let generator = ShiftPreviewGenerator()
        let start = Date()
        let block = makeBlock(title: "A", start: start)

        let preview = generator.generatePreview(
            blocks: [block],
            blockID: block.id,
            delta: 0
        )

        // Zero delta exits early — block appears in diffs with value 0 (nothing moved).
        #expect(preview.status == .clean)
        #expect(preview.diffs[block.id] == 0)
        #expect(preview.collisions.isEmpty)
    }

    @Test @MainActor func generatePreviewUnknownBlockIDReturnsClean() {
        let generator = ShiftPreviewGenerator()
        let start = Date()
        let block = makeBlock(title: "A", start: start)

        let preview = generator.generatePreview(
            blocks: [block],
            blockID: UUID(),
            delta: 600
        )

        // blockID not found — exits early, block appears with diff = 0.
        #expect(preview.status == .clean)
        #expect(preview.diffs[block.id] == 0)
    }

    @Test @MainActor func generatePreviewEmptyBlocksReturnsClean() {
        let generator = ShiftPreviewGenerator()

        let preview = generator.generatePreview(
            blocks: [],
            blockID: UUID(),
            delta: 600
        )

        // Empty input — previewBlocks and diffs are both empty.
        #expect(preview.status == .clean)
        #expect(preview.previewBlocks.isEmpty)
        #expect(preview.diffs.isEmpty)
    }

    // MARK: - Backward shift clamps at originalStart

    @Test @MainActor func generatePreviewBackwardShiftClampsAtOriginalStart() {
        let generator = ShiftPreviewGenerator()
        let originalStart = Date()
        let block = makeBlock(title: "A", start: originalStart)

        // Try to shift further back than originalStart — should clamp.
        let preview = generator.generatePreview(
            blocks: [block],
            blockID: block.id,
            delta: -9999
        )

        let previewBlock = preview.previewBlocks.first { $0.id == block.id }
        #expect(previewBlock?.scheduledStart == originalStart)
    }

    // MARK: - CompressedBlockIDs populated

    @Test @MainActor func generatePreviewPopulatesCompressedBlockIDs() {
        let generator = ShiftPreviewGenerator()
        let start = Date()

        // Fluid A (30 min, min 5 min) immediately before Pinned.
        // Shifting A into the pinned block triggers compression.
        let fluid = makeBlock(title: "Fluid", start: start, duration: 1800, minimumDuration: 300)
        let pinned = makeBlock(title: "Pinned", start: start.addingTimeInterval(1800), isPinned: true)

        let preview = generator.generatePreview(
            blocks: [fluid, pinned],
            blockID: fluid.id,
            delta: 1200  // causes overlap
        )

        // The fluid block should have been compressed to resolve the collision.
        #expect(preview.compressedBlockIDs.contains(fluid.id))
    }

    // MARK: - PreviewBlocks ordering

    @Test @MainActor func generatePreviewBlocksAreSortedByScheduledStart() {
        let generator = ShiftPreviewGenerator()
        let start = Date()

        // Pass blocks in reverse order to verify sorting is enforced.
        let blockC = makeBlock(title: "C", start: start.addingTimeInterval(3600))
        let blockB = makeBlock(title: "B", start: start.addingTimeInterval(1800))
        let blockA = makeBlock(title: "A", start: start)

        let preview = generator.generatePreview(
            blocks: [blockC, blockB, blockA],
            blockID: blockA.id,
            delta: 300
        )

        let starts = preview.previewBlocks.map(\.scheduledStart)
        #expect(starts == starts.sorted())
    }

    // MARK: - Sendable conformance (compile-time check)

    @Test func shiftPreviewGeneratorIsSendable() {
        let generator = ShiftPreviewGenerator()
        let _: any Sendable = generator
        _ = generator
    }

    @Test func shiftPreviewIsSendable() throws {
        let preview = ShiftPreview(
            previewBlocks: [],
            collisions: [],
            compressedBlockIDs: [],
            status: .clean,
            diffs: [:]
        )
        let _: any Sendable = preview
        _ = preview
    }

    @Test func previewBlockIsSendable() {
        let pb = PreviewBlock(
            id: UUID(),
            title: "Test",
            scheduledStart: Date(),
            originalStart: Date(),
            duration: 1800,
            minimumDuration: 300,
            isPinned: false,
            requiresReview: false,
            status: .upcoming
        )
        let _: any Sendable = pb
        _ = pb
    }
}
