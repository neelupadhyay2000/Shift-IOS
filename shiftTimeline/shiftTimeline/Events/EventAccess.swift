import Foundation

/// Determines a user's relationship to an event for read-only gating (SHIFT-622).
///
/// An event is *shared* (read-only for this user) only when the user is signed in
/// **and** the event has a known owner that isn't them. Everything else is treated
/// as the user's own, so local-first use is never gated:
/// - signed out (`currentProfileID == nil`) → owned (full local editing);
/// - no known owner (`ownerId == nil`, e.g. a local-only or not-yet-backfilled
///   event) → owned;
/// - owned by the current profile → owned;
/// - owned by a different profile → shared / read-only.
nonisolated enum EventAccess {

    /// `true` when the event belongs to someone else (vendor / collaborator view).
    static func isShared(ownerId: UUID?, currentProfileID: UUID?) -> Bool {
        guard let currentProfileID, let ownerId else { return false }
        return ownerId != currentProfileID
    }

    /// `true` when the current user owns the event (including local-only events).
    static func isOwner(ownerId: UUID?, currentProfileID: UUID?) -> Bool {
        !isShared(ownerId: ownerId, currentProfileID: currentProfileID)
    }
}
