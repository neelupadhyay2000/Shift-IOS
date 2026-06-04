import Foundation

/// Raised when a SwiftData model cannot be projected to a DTO because a
/// relationship the wire schema requires (a non-null foreign key) is not wired.
///
/// These represent precondition violations — a synced entity is always attached
/// to its event/track before it is mapped — so callers `try` rather than branch.
nonisolated enum ModelMappingError: Error, Equatable {
    /// A track / vendor / block / shift record was not attached to an event,
    /// so the required `event_id` could not be resolved.
    case missingEvent
    /// A block was not attached to a track, so the required `track_id` could
    /// not be resolved.
    case missingTrack
}
