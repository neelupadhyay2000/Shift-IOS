import Foundation
import Services
import Testing

/// Verifies the deterministic mapping from a successful container-build
/// attempt to a `CloudKitMirrorState`. The `PersistenceController` fallback
/// chain has five attempts; tests here lock in which state each attempt
/// produces so the UI can branch on `.degraded` to surface a sync banner.
@Suite("PersistenceController CloudKit Mirror State")
struct PersistenceControllerMirrorStateTests {

    // MARK: - .healthy

    @Test func existingStoreWithMigrationPlanReportsHealthy() {
        #expect(CloudKitMirrorState.from(attempt: .existingStoreWithPlan) == .healthy)
    }

    @Test func freshStoreWithMigrationPlanReportsHealthy() {
        #expect(CloudKitMirrorState.from(attempt: .freshStoreWithPlan) == .healthy)
    }

    // MARK: - .degraded

    @Test func freshStoreWithoutMigrationPlanReportsDegraded() {
        // CloudKit is "on" at the configuration level but the mirror cannot
        // reconcile without a matching VersionedSchema — publishing halts.
        #expect(CloudKitMirrorState.from(attempt: .freshStoreWithoutPlan) == .degraded)
    }

    // MARK: - .disabled

    @Test func localOnlyStoreReportsDisabled() {
        #expect(CloudKitMirrorState.from(attempt: .localOnly) == .disabled)
    }

    @Test func inMemoryStoreReportsDisabled() {
        #expect(CloudKitMirrorState.from(attempt: .inMemory) == .disabled)
    }

    // MARK: - Live PersistenceController exposes the property

    /// In-memory `forTesting()` containers run with `cloudKitDatabase: .none`,
    /// which is the `.disabled` path — but the property must exist and be
    /// readable for any future banner/UI consumer.
    @Test @MainActor func sharedControllerExposesMirrorState() {
        let state = PersistenceController.shared.cloudKitMirrorState
        #expect(state == .healthy || state == .degraded || state == .disabled)
    }
}
