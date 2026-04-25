import Foundation
import Services
import Testing

/// Locks in the share-with-vendor gate decision matrix. The view layer
/// (`EventDetailView`) consumes this pure helper to decide whether to
/// enqueue a `CKQueryOperation` or surface a degraded-sync error before
/// any CloudKit traffic is issued.
@Suite("CloudKit Share Gate")
struct CloudKitShareGateTests {

    @Test func healthyMirrorAllowsShareToProceed() {
        #expect(CloudKitShareGate.decide(for: .healthy) == .proceed)
    }

    @Test func degradedMirrorBlocksShareWithDistinctError() {
        // Critical: this MUST be a separate decision from "not yet synced",
        // because the user-facing copy and remediation differ ("update the
        // app" vs "wait a moment").
        let decision = CloudKitShareGate.decide(for: .degraded)
        #expect(decision == .blockDegradedSync)
        #expect(decision != .proceed)
    }

    @Test func disabledMirrorBlocksShareWithDistinctError() {
        let decision = CloudKitShareGate.decide(for: .disabled)
        #expect(decision == .blockCloudKitUnavailable)
        #expect(decision != .proceed)
    }

    @Test func degradedAndDisabledDecisionsAreNotEqual() {
        // Different remediation paths — must not collapse into a single case.
        #expect(CloudKitShareGate.decide(for: .degraded) != CloudKitShareGate.decide(for: .disabled))
    }
}
