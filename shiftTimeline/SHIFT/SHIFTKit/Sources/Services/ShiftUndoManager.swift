import Foundation
import Models

// MARK: - BlockSnapshot

/// A value-type snapshot of the mutable fields on a ``TimeBlockModel`` at a
/// single point in time.
///
/// Snapshots are captured **before** and **after** a ripple operation so that
/// ``ShiftUndoManager`` can restore any affected block to either state without
/// re-running the engine.
public struct BlockSnapshot: Codable, Sendable, Equatable {
   /// The stable identity of the block being snapshotted.
   public let blockID: UUID
   /// The scheduled start time captured at snapshot time.
   public let scheduledStart: Date
   /// The duration captured at snapshot time.
   public let duration: TimeInterval
   /// The block lifecycle status captured at snapshot time.
   public let status: BlockStatus

   public init(
       blockID: UUID,
       scheduledStart: Date,
       duration: TimeInterval,
       status: BlockStatus
   ) {
       self.blockID = blockID
       self.scheduledStart = scheduledStart
       self.duration = duration
       self.status = status
   }
}

// MARK: - BlockSnapshot + convenience

public extension BlockSnapshot {
   /// Convenience initialiser that reads the current field values directly
   /// off a live ``TimeBlockModel`` reference.
   init(capturing block: TimeBlockModel) {
       self.init(
           blockID: block.id,
           scheduledStart: block.scheduledStart,
           duration: block.duration,
           status: block.status
       )
   }
}

// MARK: - UndoEntry

/// A single undoable operation: a before-snapshot and an after-snapshot for
/// every block that was mutated by one ripple recalculation.
///
/// `before` is applied when the user taps **Undo**; `after` is re-applied when
/// the user taps **Redo**.
public struct UndoEntry: Sendable, Equatable {
   /// State of each affected block **before** the operation.
   public let before: [BlockSnapshot]
   /// State of each affected block **after** the operation.
   public let after: [BlockSnapshot]

   public init(before: [BlockSnapshot], after: [BlockSnapshot]) {
       self.before = before
       self.after = after
   }
}

// MARK: - UndoStack

/// A fixed-depth, value-type double stack that holds ``UndoEntry`` items.
///
/// When `undoStack` reaches `maxDepth`, the oldest entry is dropped to keep
/// memory bounded. `redoStack` is always cleared when a new entry is recorded.
public struct UndoStack: Sendable {

   /// Maximum number of undo levels retained.
   public static let maxDepth = 50

   private(set) var undoStack: [UndoEntry] = []
   private(set) var redoStack: [UndoEntry] = []

   public init() {}

   // MARK: Queries

   /// Whether there is at least one operation that can be undone.
   public var canUndo: Bool { !undoStack.isEmpty }

   /// Whether there is at least one operation that can be redone.
   public var canRedo: Bool { !redoStack.isEmpty }

   // MARK: Mutations

   /// Records a new undoable operation and clears the redo stack.
   ///
   /// If the undo stack already holds `maxDepth` entries, the oldest is
   /// evicted before the new entry is pushed.
   public mutating func record(_ entry: UndoEntry) {
       redoStack.removeAll()
       if undoStack.count >= Self.maxDepth {
           undoStack.removeFirst()
       }
       undoStack.append(entry)
   }

   /// Pops the most recent undo entry and pushes it onto the redo stack.
   ///
   /// - Returns: The popped ``UndoEntry``, or `nil` if the stack is empty.
   @discardableResult
   public mutating func popUndo() -> UndoEntry? {
       guard let entry = undoStack.popLast() else { return nil }
       redoStack.append(entry)
       return entry
   }

   /// Pops the most recent redo entry and pushes it back onto the undo stack.
   ///
   /// - Returns: The popped ``UndoEntry``, or `nil` if the redo stack is empty.
   @discardableResult
   public mutating func popRedo() -> UndoEntry? {
       guard let entry = redoStack.popLast() else { return nil }
       undoStack.append(entry)
       return entry
   }
}

// MARK: - ShiftUndoManager

/// Manages undo and redo for ripple-engine operations.
///
/// Call ``record(before:after:)`` immediately after every ``RippleEngine/recalculate``
/// call, passing snapshots taken before and after the mutation. Then wire
/// ``undo(applying:)`` / ``redo(applying:)`` to your UI's undo/redo actions.
///
/// `ShiftUndoManager` lives on `@MainActor` because it reads and writes
/// `TimeBlockModel` properties — SwiftData `@Model` objects that must be
/// accessed on the main context's actor.
@MainActor
public final class ShiftUndoManager {

   private var stack = UndoStack()

   /// Holds the before-snapshots captured by ``recordShift(blocks:)`` until
   /// ``commitShift(blocks:)`` or ``cancelShift()`` is called.
   private var pendingBefore: [BlockSnapshot]?

   public init() {}

   // MARK: Queries

   /// `true` when there is at least one operation that can be undone.
   public var canUndo: Bool { stack.canUndo }

   /// `true` when there is at least one operation that can be redone.
   public var canRedo: Bool { stack.canRedo }

   // MARK: - Two-phase shift recording

   /// **Phase 1.** Snapshots the current state of every block in `blocks` as
   /// the before-state for the next undo entry.
   ///
   /// Call this **before** passing blocks to ``RippleEngine/recalculate``.
   /// Follow up with ``commitShift(blocks:)`` once the engine has finished
   /// mutating the blocks, or ``cancelShift()`` if the operation is aborted.
   ///
   /// Calling `recordShift` again before committing silently replaces any
   /// pending before-state (safe for rapid successive drags).
   ///
   /// - Parameter blocks: All blocks that may be affected by the upcoming shift.
   public func recordShift(blocks: [TimeBlockModel]) {
       pendingBefore = blocks.map { BlockSnapshot(capturing: $0) }
   }

   /// **Phase 2.** Snapshots the current (post-mutation) state of every block
   /// in `blocks` as the after-state, then pushes the completed ``UndoEntry``
   /// onto the undo stack.
   ///
   /// Call this **after** ``RippleEngine/recalculate`` has finished mutating
   /// the blocks. Does nothing if ``recordShift(blocks:)`` was never called.
   ///
   /// - Parameter blocks: The same set of blocks passed to ``recordShift(blocks:)``.
   public func commitShift(blocks: [TimeBlockModel]) {
       guard let before = pendingBefore else { return }
       pendingBefore = nil
       let after = blocks.map { BlockSnapshot(capturing: $0) }
       stack.record(UndoEntry(before: before, after: after))
   }

   /// Discards any pending before-state without pushing an undo entry.
   ///
   /// Call this if a shift is cancelled or the engine returns an error before
   /// the blocks are mutated.
   public func cancelShift() {
       pendingBefore = nil
   }

   // MARK: - Low-level recording

   /// Records a new undoable operation from pre-built snapshot arrays.
   ///
   /// Prefer ``recordShift(blocks:)`` + ``commitShift(blocks:)`` for the
   /// normal ripple workflow. Use this overload when you already have both
   /// before and after snapshots (e.g. in tests or batch operations).
   ///
   /// - Parameters:
   ///   - before: Snapshots of every affected block captured **before** mutation.
   ///   - after:  Snapshots of every affected block captured **after** mutation.
   public func record(before: [BlockSnapshot], after: [BlockSnapshot]) {
       let entry = UndoEntry(before: before, after: after)
       stack.record(entry)
   }

   // MARK: Undo / Redo

   /// Undoes the most recent operation by restoring the `before` snapshots
   /// onto the live block references supplied by `blocks`.
   ///
   /// - Parameter blocks: All live `TimeBlockModel` instances in the current
   ///   SwiftData context. The manager looks up each block by its `id` and
   ///   writes the snapshot values back.
   /// - Returns: `true` if an undo entry was available and applied.
   @discardableResult
   public func undo(applying blocks: [TimeBlockModel]) -> Bool {
       guard let entry = stack.popUndo() else { return false }
       apply(snapshots: entry.before, to: blocks)
       return true
   }

   /// Redoes the most recently undone operation by restoring the `after`
   /// snapshots onto the live block references supplied by `blocks`.
   ///
   /// - Parameter blocks: All live `TimeBlockModel` instances in the current
   ///   SwiftData context.
   /// - Returns: `true` if a redo entry was available and applied.
   @discardableResult
   public func redo(applying blocks: [TimeBlockModel]) -> Bool {
       guard let entry = stack.popRedo() else { return false }
       apply(snapshots: entry.after, to: blocks)
       return true
   }

   // MARK: Private

   /// Applies a set of snapshots to matching live block references.
   ///
   /// Blocks whose `id` does not appear in `snapshots` are left untouched.
   /// This is intentional — a partial ripple may only affect a subset of the
   /// timeline.
   private func apply(snapshots: [BlockSnapshot], to blocks: [TimeBlockModel]) {
       let blockByID = Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, $0) })
       for snapshot in snapshots {
           guard let block = blockByID[snapshot.blockID] else { continue }
           block.scheduledStart = snapshot.scheduledStart
           block.duration = snapshot.duration
           block.status = snapshot.status
       }
   }
}
