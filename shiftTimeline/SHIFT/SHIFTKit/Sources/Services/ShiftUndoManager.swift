import Foundation
import Observation
import Models

// MARK: - BlockSnapshot

/// Value-type snapshot of mutable fields on a ``TimeBlockModel`` for undo/redo.
public struct BlockSnapshot: Codable, Sendable, Equatable {
    public let blockID: UUID
    public let scheduledStart: Date
    public let duration: TimeInterval
    public let status: BlockStatus
    /// Included so undo/redo restores the full engine-mutated state.
    public let requiresReview: Bool

    public init(
        blockID: UUID,
        scheduledStart: Date,
        duration: TimeInterval,
        status: BlockStatus,
        requiresReview: Bool
    ) {
        self.blockID = blockID
        self.scheduledStart = scheduledStart
        self.duration = duration
        self.status = status
        self.requiresReview = requiresReview
    }
}

// MARK: - BlockSnapshot + convenience

public extension BlockSnapshot {
    init(capturing block: TimeBlockModel) {
        self.init(
            blockID: block.id,
            scheduledStart: block.scheduledStart,
            duration: block.duration,
            status: block.status,
            requiresReview: block.requiresReview
        )
    }
}

// MARK: - UndoEntry

/// One undoable operation: before/after snapshots for every mutated block.
public struct UndoEntry: Sendable, Equatable {
    public let before: [BlockSnapshot]
    public let after: [BlockSnapshot]

    public init(before: [BlockSnapshot], after: [BlockSnapshot]) {
        self.before = before
        self.after = after
    }
}

// MARK: - UndoStack

/// Fixed-depth double stack for undo/redo entries. Oldest entry dropped at `maxDepth`.
public struct UndoStack: Sendable {

    /// Maximum number of undo levels retained.
    public static let maxDepth = 50
    private(set) var undoStack: [UndoEntry] = []
    private(set) var redoStack: [UndoEntry] = []

    public init() {}

    // MARK: Queries

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    // MARK: Mutations

    /// Records a new entry and clears the redo stack. Evicts oldest if at `maxDepth`.
    public mutating func record(_ entry: UndoEntry) {
        redoStack.removeAll()
        if undoStack.count >= Self.maxDepth {
            undoStack.removeFirst()
        }
        undoStack.append(entry)
    }

    @discardableResult
    public mutating func popUndo() -> UndoEntry? {
        guard let entry = undoStack.popLast() else { return nil }
        redoStack.append(entry)
        return entry
    }

    @discardableResult
    public mutating func popRedo() -> UndoEntry? {
        guard let entry = redoStack.popLast() else { return nil }
        undoStack.append(entry)
        return entry
    }
}

// MARK: - ShiftUndoManager

/// Undo/redo manager for ripple-engine block mutations. Lives on `@MainActor`.
@Observable
@MainActor
public final class ShiftUndoManager {

    private var stack = UndoStack()

    /// Holds the before-snapshots captured by ``recordShift(blocks:)`` until
    /// ``commitShift(blocks:)`` or ``cancelShift()`` is called.
    private var pendingBefore: [BlockSnapshot]?

    public init() {}

    // MARK: Queries

    public var canUndo: Bool { stack.canUndo }
    public var canRedo: Bool { stack.canRedo }

    // MARK: - Two-phase shift recording

    /// Snapshots current block state as before-state. Call before `RippleEngine.recalculate`.
    public func recordShift(blocks: [TimeBlockModel]) {
        pendingBefore = blocks.map { BlockSnapshot(capturing: $0) }
    }

    /// Snapshots post-mutation state and pushes the completed entry. Call after `RippleEngine.recalculate`.
    public func commitShift(blocks: [TimeBlockModel]) {
        guard let before = pendingBefore else { return }
        pendingBefore = nil
        let after = blocks.map { BlockSnapshot(capturing: $0) }
        stack.record(UndoEntry(before: before, after: after))
    }

    /// Discards pending before-state without pushing an entry.
    public func cancelShift() {
        pendingBefore = nil
    }

    // MARK: - Low-level recording

    public func record(before: [BlockSnapshot], after: [BlockSnapshot]) {
        stack.record(UndoEntry(before: before, after: after))
    }

    // MARK: - Undo / Redo

    /// Pops the most recent undo entry and returns the before-snapshots to apply.
    public func undo() -> [BlockSnapshot]? {
        guard let entry = stack.popUndo() else { return nil }
        return entry.before
    }

    /// Pops the most recent redo entry and returns the after-snapshots to apply.
    public func redo() -> [BlockSnapshot]? {
        guard let entry = stack.popRedo() else { return nil }
        return entry.after
    }

    // MARK: - Convenience applying overloads

    @discardableResult
    public func undo(applying blocks: [TimeBlockModel]) -> Bool {
        guard let snapshots = undo() else { return false }
        apply(snapshots: snapshots, to: blocks)
        return true
    }

    @discardableResult
    public func redo(applying blocks: [TimeBlockModel]) -> Bool {
        guard let snapshots = redo() else { return false }
        apply(snapshots: snapshots, to: blocks)
        return true
    }

    // MARK: - Private

    /// Applies a set of snapshots to matching live block references.
    ///
    /// Blocks whose `id` does not appear in `snapshots` are left untouched —
    /// a partial ripple may only affect a subset of the timeline.
    ///
    /// The lookup dictionary is built with `reduce(into:)` rather than
    /// `Dictionary(uniqueKeysWithValues:)` to avoid a runtime trap if `blocks`
    /// contains duplicate IDs (e.g. the same object passed twice). The last
    /// occurrence wins, matching natural dictionary-insert semantics.
    private func apply(snapshots: [BlockSnapshot], to blocks: [TimeBlockModel]) {
        let blockByID = blocks.reduce(into: [UUID: TimeBlockModel]()) { dict, block in
            dict[block.id] = block
        }
        for snapshot in snapshots {
            guard let block = blockByID[snapshot.blockID] else { continue }
            block.scheduledStart = snapshot.scheduledStart
            block.duration = snapshot.duration
            block.status = snapshot.status
            block.requiresReview = snapshot.requiresReview
        }
    }
}
