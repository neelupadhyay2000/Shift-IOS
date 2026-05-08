import Foundation

/// Health of the CloudKit mirror. `.degraded` → show sync banner; `.disabled` → CloudKit off.
public enum CloudKitMirrorState: Sendable, Equatable {
    /// Mirror healthy — migration-plan-backed container opened successfully.
    case healthy

    /// CloudKit enabled but schema unreconciled — mirror publishing silently halted.
    case degraded

    /// Local-only or in-memory container. CloudKit fully off.
    case disabled
}

/// Which fallback attempt produced the live `ModelContainer`. Unit-testable mapping.
public enum CloudKitMirrorAttempt: Sendable {
    case existingStoreWithPlan
    case freshStoreWithPlan
    case freshStoreWithoutPlan
    case localOnly
    case inMemory
}

public extension CloudKitMirrorState {
    /// Maps fallback attempt to mirror state.
    static func from(attempt: CloudKitMirrorAttempt) -> CloudKitMirrorState {
        switch attempt {
        case .existingStoreWithPlan, .freshStoreWithPlan:
            return .healthy
        case .freshStoreWithoutPlan:
            return .degraded
        case .localOnly, .inMemory:
            return .disabled
        }
    }
}
