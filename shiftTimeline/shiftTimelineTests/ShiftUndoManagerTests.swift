import Foundation
import Models
import Services
import Testing

// MARK: - ShiftUndoManagerTests

struct ShiftUndoManagerTests {

    // MARK: - Helpers

    /// Creates a TimeBlockModel with a known start and duration.
    @MainActor
    private func makeBlock(
        title: String = "Block",
        start: Date = Date(),
        duration: TimeInterval = 1800
    ) -> TimeBlockModel {
        TimeBlockModel(title: title, scheduledStart: start, duration: duration)
    }

    /// Snapshots the current mutable state of a block.
    private func snapshot(_ block: TimeBlockModel) -> BlockSnapshot {
        BlockSnapshot(capturing: block)
    }

    // MARK: - canUndo / canRedo initial state

    @Test @MainActor func initialStateCannotUndoOrRedo() {
        let manager = ShiftUndoManager()
        #expect(manager.canUndo == false)
        #expect(manager.canRedo == false)
    }

    // MARK: - record

    @Test @MainActor func recordMakesCanUndoTrue() {
        let manager = ShiftUndoManager()
        let block = makeBlock()
        let before = [snapshot(block)]
        block.scheduledStart = block.scheduledStart.addingTimeInterval(600)
        let after = [snapshot(block)]

        manager.record(before: before, after: after)

        #expect(manager.canUndo == true)
        #expect(manager.canRedo == false)
    }

    @Test @MainActor func recordClearsRedoStack() {
        let manager = ShiftUndoManager()
        let block = makeBlock()
        let originalStart = block.scheduledStart

        // Record first op
        let before1 = [snapshot(block)]
        block.scheduledStart = block.scheduledStart.addingTimeInterval(600)
        let after1 = [snapshot(block)]
        manager.record(before: before1, after: after1)

        // Undo to populate redo stack
        manager.undo(applying: [block])
        #expect(manager.canRedo == true)

        // Record a new op — redo stack must be cleared
        block.scheduledStart = originalStart.addingTimeInterval(300)
        let before2 = [BlockSnapshot(capturing: block)]
        block.scheduledStart = originalStart.addingTimeInterval(900)
        let after2 = [BlockSnapshot(capturing: block)]
        manager.record(before: before2, after: after2)

        #expect(manager.canRedo == false)
        #expect(manager.canUndo == true)
    }

    // MARK: - undo

    @Test @MainActor func undoRestoresBeforeSnapshot() {
        let manager = ShiftUndoManager()
        let start = Date()
        let block = makeBlock(start: start)

        let before = [snapshot(block)]                              // start
        block.scheduledStart = start.addingTimeInterval(600)
        let after = [snapshot(block)]                               // start + 10 min

        manager.record(before: before, after: after)
        let applied = manager.undo(applying: [block])

        #expect(applied == true)
        #expect(block.scheduledStart == start)
    }

    @Test @MainActor func undoMovesEntryToRedoStack() {
        let manager = ShiftUndoManager()
        let block = makeBlock()
        let before = [snapshot(block)]
        block.scheduledStart = block.scheduledStart.addingTimeInterval(300)
        let after = [snapshot(block)]
        manager.record(before: before, after: after)

        manager.undo(applying: [block])

        #expect(manager.canUndo == false)
        #expect(manager.canRedo == true)
    }

    @Test @MainActor func undoOnEmptyStackReturnsFalse() {
        let manager = ShiftUndoManager()
        let block = makeBlock()
        let result = manager.undo(applying: [block])
        #expect(result == false)
    }

    @Test @MainActor func undoRestoresMultipleBlocks() {
        let manager = ShiftUndoManager()
        let start = Date()
        let blockA = makeBlock(title: "A", start: start)
        let blockB = makeBlock(title: "B", start: start.addingTimeInterval(1800))

        let before = [snapshot(blockA), snapshot(blockB)]
        blockA.scheduledStart = start.addingTimeInterval(600)
        blockB.scheduledStart = start.addingTimeInterval(2400)
        let after = [snapshot(blockA), snapshot(blockB)]

        manager.record(before: before, after: after)
        manager.undo(applying: [blockA, blockB])

        #expect(blockA.scheduledStart == start)
        #expect(blockB.scheduledStart == start.addingTimeInterval(1800))
    }

    // MARK: - redo

    @Test @MainActor func redoRestoresAfterSnapshot() {
        let manager = ShiftUndoManager()
        let start = Date()
        let shiftedStart = start.addingTimeInterval(600)
        let block = makeBlock(start: start)

        let before = [snapshot(block)]
        block.scheduledStart = shiftedStart
        let after = [snapshot(block)]

        manager.record(before: before, after: after)
        manager.undo(applying: [block])       // block back to start
        let applied = manager.redo(applying: [block])  // block back to shiftedStart

        #expect(applied == true)
        #expect(block.scheduledStart == shiftedStart)
    }

    @Test @MainActor func redoMovesEntryBackToUndoStack() {
        let manager = ShiftUndoManager()
        let block = makeBlock()
        let before = [snapshot(block)]
        block.scheduledStart = block.scheduledStart.addingTimeInterval(300)
        let after = [snapshot(block)]
        manager.record(before: before, after: after)

        manager.undo(applying: [block])
        manager.redo(applying: [block])

        #expect(manager.canUndo == true)
        #expect(manager.canRedo == false)
    }

    @Test @MainActor func redoOnEmptyStackReturnsFalse() {
        let manager = ShiftUndoManager()
        let block = makeBlock()
        let result = manager.redo(applying: [block])
        #expect(result == false)
    }

    // MARK: - Stack depth cap

    @Test @MainActor func stackCapsAtMaxDepth() {
        let manager = ShiftUndoManager()
        let block = makeBlock()

        // Record maxDepth + 10 operations
        let overLimit = UndoStack.maxDepth + 10
        for i in 0..<overLimit {
            let before = [BlockSnapshot(
                blockID: block.id,
                scheduledStart: block.scheduledStart,
                duration: block.duration,
                status: block.status,
                requiresReview: block.requiresReview
            )]
            block.scheduledStart = block.scheduledStart.addingTimeInterval(Double(i) * 60)
            let after = [BlockSnapshot(capturing: block)]
            manager.record(before: before, after: after)
        }

        // Only maxDepth undos should be available
        var undoCount = 0
        while manager.canUndo {
            manager.undo(applying: [block])
            undoCount += 1
        }
        #expect(undoCount == UndoStack.maxDepth)
    }

    // MARK: - Multi-level undo/redo sequence

    @Test @MainActor func multiLevelUndoRedoMaintainsOrder() {
        let manager = ShiftUndoManager()
        let start = Date()
        let block = makeBlock(start: start)

        // Op 1: shift +10 min
        let before1 = [snapshot(block)]
        block.scheduledStart = start.addingTimeInterval(600)
        let after1 = [snapshot(block)]
        manager.record(before: before1, after: after1)

        // Op 2: shift another +5 min
        let before2 = [snapshot(block)]
        block.scheduledStart = start.addingTimeInterval(900)
        let after2 = [snapshot(block)]
        manager.record(before: before2, after: after2)

        // Undo op 2 → block at +10 min
        manager.undo(applying: [block])
        #expect(block.scheduledStart == start.addingTimeInterval(600))

        // Undo op 1 → block back to original start
        manager.undo(applying: [block])
        #expect(block.scheduledStart == start)

        // Redo op 1 → block at +10 min
        manager.redo(applying: [block])
        #expect(block.scheduledStart == start.addingTimeInterval(600))

        // Redo op 2 → block at +15 min
        manager.redo(applying: [block])
        #expect(block.scheduledStart == start.addingTimeInterval(900))
    }

    // MARK: - Snapshot ignores unknown block IDs

    @Test @MainActor func undoIgnoresSnapshotsForUnknownBlocks() {
        let manager = ShiftUndoManager()
        let start = Date()
        let block = makeBlock(start: start)

        // Record a snapshot for a completely different UUID
        let ghostSnapshot = BlockSnapshot(
            blockID: UUID(),
            scheduledStart: start.addingTimeInterval(9999),
            duration: 3600,
            status: .upcoming,
            requiresReview: false
        )
        let realBefore = [snapshot(block)]
        block.scheduledStart = start.addingTimeInterval(600)
        let after = [snapshot(block), ghostSnapshot]

        // Before = real block only; after includes ghost
        manager.record(before: realBefore, after: after)
        manager.undo(applying: [block])

        // Block should be restored; ghost had no matching live block — no crash
        #expect(block.scheduledStart == start)
    }

    // MARK: - BlockSnapshot convenience init

    @Test @MainActor func blockSnapshotCapturesCurrentValues() {
        let start = Date()
        let block = makeBlock(start: start, duration: 3600)
        let s = BlockSnapshot(capturing: block)

        #expect(s.blockID == block.id)
        #expect(s.scheduledStart == start)
        #expect(s.duration == 3600)
        #expect(s.status == block.status)
    }

    // MARK: - UndoStack value semantics

    @Test func undoStackIsValueType() {
        var stack1 = UndoStack()
        let entry = UndoEntry(
            before: [BlockSnapshot(blockID: UUID(), scheduledStart: Date(), duration: 600, status: .upcoming, requiresReview: false)],
            after:  [BlockSnapshot(blockID: UUID(), scheduledStart: Date(), duration: 600, status: .upcoming, requiresReview: false)]
        )
        stack1.record(entry)
        var stack2 = stack1   // copy
        stack2.popUndo()

        // stack1 unchanged, stack2 popped
        #expect(stack1.canUndo == true)
        #expect(stack2.canUndo == false)
    }

    // MARK: - recordShift / commitShift / cancelShift

    /// AC 1: canUndo is true after a recordShift + commitShift pair.
    @Test @MainActor func recordShiftThenCommitMakesCanUndoTrue() {
        let manager = ShiftUndoManager()
        let block = makeBlock()

        manager.recordShift(blocks: [block])
        block.scheduledStart = block.scheduledStart.addingTimeInterval(600)
        manager.commitShift(blocks: [block])

        #expect(manager.canUndo == true)
        #expect(manager.canRedo == false)
    }

    /// AC 2: 51 recordShift+commitShift calls produce exactly 50 undo entries;
    /// the oldest (first) entry is evicted.
    @Test @MainActor func recordShift51TimesKeepsOnly50Entries() {
        let manager = ShiftUndoManager()
        let block = makeBlock()
        let firstStart = block.scheduledStart

        for i in 1...51 {
            manager.recordShift(blocks: [block])
            block.scheduledStart = block.scheduledStart.addingTimeInterval(Double(i) * 60)
            manager.commitShift(blocks: [block])
        }

        // Count available undos
        var undoCount = 0
        while manager.canUndo {
            manager.undo(applying: [block])
            undoCount += 1
        }
        #expect(undoCount == UndoStack.maxDepth)

        // After 50 undos the block should NOT be back at firstStart because
        // the very first entry (which would restore firstStart) was evicted.
        #expect(block.scheduledStart != firstStart)
    }

    /// AC 3: The before-snapshot values captured by recordShift match the
    /// block's properties at call time, and are correctly restored by undo.
    @Test @MainActor func recordShiftSnapshotValuesMatchBlockProperties() {
        let manager = ShiftUndoManager()
        let start = Date()
        let block = makeBlock(start: start, duration: 3600)

        // Capture before-state via recordShift
        manager.recordShift(blocks: [block])

        // Mutate the block (simulating what the ripple engine would do)
        let shiftedStart = start.addingTimeInterval(900)
        block.scheduledStart = shiftedStart
        block.duration = 2700

        manager.commitShift(blocks: [block])

        // Undo should restore the values that were present at recordShift time
        manager.undo(applying: [block])

        #expect(block.scheduledStart == start)
        #expect(block.duration == 3600)
    }

    /// commitShift without a prior recordShift is a no-op — no entry pushed.
    @Test @MainActor func commitShiftWithoutRecordShiftIsNoop() {
        let manager = ShiftUndoManager()
        let block = makeBlock()

        manager.commitShift(blocks: [block])

        #expect(manager.canUndo == false)
    }

    /// cancelShift discards the pending before-state; commitShift after cancel is a no-op.
    @Test @MainActor func cancelShiftDiscardsBeforeState() {
        let manager = ShiftUndoManager()
        let block = makeBlock()

        manager.recordShift(blocks: [block])
        manager.cancelShift()

        block.scheduledStart = block.scheduledStart.addingTimeInterval(600)
        manager.commitShift(blocks: [block])  // should be ignored

        #expect(manager.canUndo == false)
    }

    /// A second recordShift before commit replaces the pending before-state.
    @Test @MainActor func secondRecordShiftReplacesPending() {
        let manager = ShiftUndoManager()
        let start = Date()
        let block = makeBlock(start: start)

        // First recordShift — captures start
        manager.recordShift(blocks: [block])

        // Move block before calling commit (simulating rapid re-drag)
        block.scheduledStart = start.addingTimeInterval(300)

        // Second recordShift — should replace the pending before with +5 min state
        manager.recordShift(blocks: [block])

        // Now mutate to final position and commit
        block.scheduledStart = start.addingTimeInterval(900)
        manager.commitShift(blocks: [block])

        // Undo should restore to the second recordShift's snapshot (+5 min), not original start
        manager.undo(applying: [block])
        #expect(block.scheduledStart == start.addingTimeInterval(300))
    }

    // MARK: - undo() -> [BlockSnapshot]?

    /// AC 1: Returned snapshots contain the pre-shift (before) values.
    @Test @MainActor func undoReturnsPreShiftSnapshots() throws {
        let manager = ShiftUndoManager()
        let start = Date()
        let block = makeBlock(start: start, duration: 1800)

        let beforeSnapshot = snapshot(block)
        block.scheduledStart = start.addingTimeInterval(600)
        block.duration = 900
        manager.record(before: [beforeSnapshot], after: [snapshot(block)])

        let returned = manager.undo()

        let s = try #require(returned?.first)
        #expect(s.blockID == block.id)
        #expect(s.scheduledStart == start)
        #expect(s.duration == 1800)
    }

    /// AC 2: After undo() on a single entry — canUndo = false, canRedo = true.
    @Test @MainActor func undoSingleEntryLeavesCanUndoFalseCanRedoTrue() {
        let manager = ShiftUndoManager()
        let block = makeBlock()

        let before = [snapshot(block)]
        block.scheduledStart = block.scheduledStart.addingTimeInterval(600)
        manager.record(before: before, after: [snapshot(block)])

        _ = manager.undo()

        #expect(manager.canUndo == false)
        #expect(manager.canRedo == true)
    }

    /// AC 3: undo() on an empty stack returns nil.
    @Test @MainActor func undoOnEmptyStackReturnsNil() {
        let manager = ShiftUndoManager()
        let result = manager.undo()
        #expect(result == nil)
    }

    /// redo() returns after-snapshots and leaves canRedo=false, canUndo=true.
    @Test @MainActor func redoReturnsPostShiftSnapshots() throws {
        let manager = ShiftUndoManager()
        let start = Date()
        let shiftedStart = start.addingTimeInterval(600)
        let block = makeBlock(start: start)

        manager.record(before: [snapshot(block)],
                       after: [BlockSnapshot(blockID: block.id,
                                             scheduledStart: shiftedStart,
                                             duration: block.duration,
                                             status: block.status,
                                             requiresReview: block.requiresReview)])

        _ = manager.undo()                  // populate redo stack
        let returned = manager.redo()

        let s = try #require(returned?.first)
        #expect(s.scheduledStart == shiftedStart)
        #expect(manager.canRedo == false)
        #expect(manager.canUndo == true)
    }

    /// redo() on an empty redo stack returns nil.
    @Test @MainActor func redoOnEmptyStackReturnsNil() {
        let manager = ShiftUndoManager()
        let result = manager.redo()
        #expect(result == nil)
    }

    // MARK: - recordShift clears redo stack

    /// AC 1: record → undo → recordShift NEW → canRedo = false.
    ///
    /// Verifies that committing a brand-new shift via the two-phase API
    /// wipes the redo stack, not just the low-level record(before:after:) path.
    @Test @MainActor func recordShiftAfterUndoClearsRedoStack() {
        let manager = ShiftUndoManager()
        let start = Date()
        let block = makeBlock(start: start)

        // Op 1 via low-level record
        let before1 = [snapshot(block)]
        block.scheduledStart = start.addingTimeInterval(600)
        manager.record(before: before1, after: [snapshot(block)])

        // Undo → redo stack now has 1 entry
        _ = manager.undo()
        #expect(manager.canRedo == true)

        // New shift via two-phase API
        block.scheduledStart = start.addingTimeInterval(300)
        manager.recordShift(blocks: [block])
        block.scheduledStart = start.addingTimeInterval(900)
        manager.commitShift(blocks: [block])

        #expect(manager.canRedo == false)
        #expect(manager.canUndo == true)
    }

    /// AC 2: 5 undos → 1 new shift → all 5 redo entries are gone.
    @Test @MainActor func newShiftAfter5UndosClearsAllRedoEntries() {
        let manager = ShiftUndoManager()
        let start = Date()
        let block = makeBlock(start: start)

        // Push 5 operations onto the undo stack
        for i in 1...5 {
            let before = [snapshot(block)]
            block.scheduledStart = start.addingTimeInterval(Double(i) * 600)
            manager.record(before: before, after: [snapshot(block)])
        }

        // Undo all 5 → redo stack has 5 entries
        for _ in 1...5 { _ = manager.undo() }
        #expect(manager.canRedo == true)
        #expect(manager.canUndo == false)

        // Commit a brand-new shift via the two-phase API
        manager.recordShift(blocks: [block])
        block.scheduledStart = start.addingTimeInterval(300)
        manager.commitShift(blocks: [block])

        // All redo entries must be gone
        #expect(manager.canRedo == false)
        #expect(manager.canUndo == true)
    }
}
