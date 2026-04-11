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

    // MARK: - Diffs

    /// Forward shift: diffs should be populated for the shifted block and all
    /// subsequent fluid blocks; unchanged blocks should not appear in diffs.
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

    /// Unchanged blocks (pinned, or not downstream) must not appear in diffs.
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

        #expect(preview.diffs[blockA.id] != nil)
        // Pinned block does not move, so it must not appear in diffs.
        #expect(preview.diffs[pinned.id] == nil)
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
        #expect(preview.diffs.isEmpty)
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

        #expect(preview.status == .clean)
        #expect(preview.diffs.isEmpty)
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

        #expect(preview.status == .clean)
        #expect(preview.diffs.isEmpty)
    }

    @Test @MainActor func generatePreviewEmptyBlocksReturnsClean() {
        let generator = ShiftPreviewGenerator()

        let preview = generator.generatePreview(
            blocks: [],
            blockID: UUID(),
            delta: 600
        )

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
