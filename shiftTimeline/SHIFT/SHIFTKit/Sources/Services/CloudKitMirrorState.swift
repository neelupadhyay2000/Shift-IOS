import Foundation

/// Reports the health of the CloudKit mirror that backs SwiftData.
///
/// Set by `PersistenceController` based on which fallback attempt actually
/// produced the live `ModelContainer`. UI consumers branch on this to surface
/// a sync banner: `.degraded` means the user must update the app to resume
/// publishing; `.disabled` means CloudKit is not running at all.
public enum CloudKitMirrorState: Sendable, Equatable {
    /// Migration-plan-backed `ModelContainer` opened successfully — mirror
    /// is publishing and consuming records normally.
    case healthy

    /// CloudKit-enabled `ModelContainer` opened, but without a matching
    /// `VersionedSchema`. The mirror cannot reconcile and silently halts
    /// publishing. The app must be updated (new schema) to recover.
    case degraded

    /// `ModelContainer` is local-only or in-memory. CloudKit is fully off.
    case disabled
}

/// Identifies which entry in `PersistenceController`'s fallback chain
/// produced the live `ModelContainer`. Pure, data-only — no I/O — so the
/// `attempt → state` mapping is unit-testable in isolation.
public enum CloudKitMirrorAttempt: Sendable {
    case existingStoreWithPlan
    case freshStoreWithPlan
    case freshStoreWithoutPlan
    case localOnly
    case inMemory
}

public extension CloudKitMirrorState {
    /// Pure mapping from "which fallback attempt succeeded" to the resulting
    /// mirror state. Locked down by `PersistenceControllerMirrorStateTests`.
    static func from(attempt: CloudKitMirrorAttempt) -> CloudKitMirrorState {
        switch attempt {
        case .existingStoreWithPlan, .freshStoreWithPlan:
            return .healthy
        case .freshStoreWithoutPlan:
            // CloudKit is requested but the schema cannot be reconciled —
            // mirror publishing silently halts. The user must update the app.
            return .degraded
        case .localOnly, .inMemory:
            return .disabled
        }
    }
}
