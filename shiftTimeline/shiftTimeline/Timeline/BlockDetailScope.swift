import Foundation
import Models

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

extension TimeBlockModel {
    /// Whether `profileID` (a signed-in vendor) is assigned to this block via
    /// `block_vendors`. Drives the "assigned to you" indicator a vendor sees in
    /// the read-only shared timeline so they can tell, at a glance, which blocks
    /// are theirs. `nil` / unmatched ⇒ `false` (owners pass `nil`).
    func isAssigned(to profileID: UUID?) -> Bool {
        guard let profileID else { return false }
        return (vendors ?? []).contains { $0.profileId == profileID }
    }
}
