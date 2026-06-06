import Foundation

/// Per-block detail scoping for shared (read-only) events (SHIFT-630).
///
/// A vendor viewing an event shared to them sees a block's full, potentially
/// private detail — notes, voice memo, the vendor roster, dependencies — only for
/// blocks they're assigned to (via `block_vendors`). Unassigned blocks show just
/// the scheduling context (title, time, location). The owner (editable,
/// `isReadOnly == false`) always sees full detail.
nonisolated enum BlockDetailScope {

    /// Whether the viewer may see a block's full detail.
    ///
    /// - Parameters:
    ///   - isReadOnly: `true` for a vendor's shared-event view; `false` for the owner.
    ///   - assignedProfileIDs: profile ids of the vendors assigned to the block
    ///     (from `block.vendors`; only claimed vendors carry a profile id).
    ///   - currentProfileID: the signed-in profile, or `nil` when signed out.
    static func showsFullDetail(
        isReadOnly: Bool,
        assignedProfileIDs: [UUID],
        currentProfileID: UUID?
    ) -> Bool {
        guard isReadOnly else { return true }
        guard let currentProfileID else { return false }
        return assignedProfileIDs.contains(currentProfileID)
    }
}
