import Foundation

/// Pure decision helper for the share-with-vendor entry point.
///
/// `EventDetailView` calls `CloudKitShareGate.decide(for:)` *before* enqueueing
/// any `CKQueryOperation`. This separates the gate logic from the view so it
/// can be unit-tested without spinning up MainActor UI. It also guarantees
/// that a degraded mirror surfaces a distinct, actionable error rather than
/// the generic "not yet synced — please wait" message which would loop the
/// user forever.
public enum CloudKitShareGateDecision: Sendable, Equatable {
    /// Mirror is healthy — proceed with the existing CKQuery + CKShare flow.
    case proceed

    /// Mirror is `.degraded` — sync is silently halted. Show a "please update
    /// the app to resume sync" message; do NOT issue any CloudKit traffic.
    case blockDegradedSync

    /// Mirror is `.disabled` — local-only or in-memory store. Show a
    /// "CloudKit unavailable" message; do NOT issue any CloudKit traffic.
    case blockCloudKitUnavailable
}

public enum CloudKitShareGate {
    /// Returns the decision for a given mirror state. Pure, synchronous.
    public static func decide(for state: CloudKitMirrorState) -> CloudKitShareGateDecision {
        switch state {
        case .healthy:
            return .proceed
        case .degraded:
            return .blockDegradedSync
        case .disabled:
            return .blockCloudKitUnavailable
        }
    }
}
