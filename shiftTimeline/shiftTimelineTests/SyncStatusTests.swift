import Foundation
import Services
@testable import shiftTimeline
import Testing

/// SHIFT-664 — the user-facing sync status. Pure derivation (`SyncHealth`,
/// `SyncErrorState`, message mapping) plus the observable `SyncStatusMonitor`
/// driven through the diagnostics funnel.
@Suite("Sync status (SHIFT-664)")
struct SyncStatusTests {

    // MARK: - SyncHealth precedence

    @Test("status precedence: degraded beats pending beats healthy")
    func statusPrecedence() {
        #expect(SyncHealth(pendingWrites: 0, hasUnresolvedError: false).status == .healthy)
        #expect(SyncHealth(pendingWrites: 3, hasUnresolvedError: false).status == .pending)
        #expect(SyncHealth(pendingWrites: 0, hasUnresolvedError: true).status == .degraded)
        // An error wins even with writes still queued — it's the actionable state.
        #expect(SyncHealth(pendingWrites: 3, hasUnresolvedError: true).status == .degraded)
    }

    // MARK: - SyncErrorState folding

    private func event(_ category: DiagnosticEvent.Category, _ name: String, _ severity: DiagnosticEvent.Severity) -> DiagnosticEvent {
        DiagnosticEvent(category: category, name: name, severity: severity)
    }

    @Test("an error marks its stage failing; the next success in that stage clears it")
    func errorThenSuccessClears() {
        var state = SyncErrorState()
        state.ingest(event(.push, "outboxEntryParked", .error))
        #expect(state.hasUnresolvedError)
        #expect(state.failingStages == [.push])

        state.ingest(event(.push, "outboxDrained", .info))
        #expect(!state.hasUnresolvedError)
    }

    @Test("a warning (transient retry) never degrades the status")
    func warningDoesNotDegrade() {
        var state = SyncErrorState()
        state.ingest(event(.push, "outboxFlushRetry", .warning))
        #expect(!state.hasUnresolvedError)
    }

    @Test("a success in a different stage doesn't clear another stage's error")
    func crossStageSuccessDoesNotClear() {
        var state = SyncErrorState()
        state.ingest(event(.fetch, "hydrationFetchFailed", .error))
        state.ingest(event(.push, "outboxDrained", .info)) // different stage
        #expect(state.failingStages == [.fetch]) // fetch still failing
    }

    @Test("the notify category isn't a sync stage and is ignored")
    func notifyIgnored() {
        var state = SyncErrorState()
        state.ingest(event(.notify, "someNotifyError", .error))
        #expect(!state.hasUnresolvedError)
    }

    @Test("primary failing stage is the most user-relevant of several")
    func primaryFailingStagePriority() {
        var state = SyncErrorState()
        state.ingest(event(.conflict, "x", .error))
        state.ingest(event(.push, "y", .error))
        state.ingest(event(.subscribe, "z", .error))
        #expect(state.primaryFailingStage == .push) // push outranks subscribe/conflict
    }

    // MARK: - Messages

    @Test("healthy has no message; pending and degraded do")
    func messagePresence() {
        #expect(SyncStatusMessage.text(for: .healthy, failingStage: nil, pendingWrites: 0) == nil)
        #expect(SyncStatusMessage.text(for: .pending, failingStage: nil, pendingWrites: 2) != nil)
        #expect(SyncStatusMessage.text(for: .degraded, failingStage: .push, pendingWrites: 0) != nil)
    }

    @Test("degraded message is tailored to the failing stage")
    func degradedMessagePerStage() {
        #expect(SyncStatusMessage.degradedText(for: .auth) != SyncStatusMessage.degradedText(for: .push))
        #expect(SyncStatusMessage.degradedText(for: .fetch) != SyncStatusMessage.degradedText(for: .subscribe))
        // An unknown / nil stage still yields a non-empty fallback.
        #expect(!SyncStatusMessage.degradedText(for: nil).isEmpty)
    }

    // MARK: - SyncStatusMonitor (live folding)

    @MainActor
    @Test("the monitor reflects pending writes, then degrades on error, then recovers")
    func monitorLifecycle() {
        // A controllable pending-count source standing in for the Outbox depth.
        final class Pending { var count = 0 }
        let pending = Pending()
        let center = SyncDiagnosticsCenter(
            defaults: .standard, storageKey: "test.\(UUID().uuidString)", maxEvents: 50
        )
        let monitor = SyncStatusMonitor(diagnostics: center, pendingWriteCount: { pending.count })

        #expect(monitor.status == .healthy)

        // A queued write → pending.
        pending.count = 2
        monitor.refreshPending()
        #expect(monitor.status == .pending)
        #expect(monitor.message != nil)

        // A push error while it's pending → degraded wins.
        monitor.ingest(DiagnosticEvent(category: .push, name: "outboxEntryParked", severity: .error))
        #expect(monitor.status == .degraded)

        // The queue drains: count back to 0 and a success clears the stage → healthy.
        pending.count = 0
        monitor.ingest(DiagnosticEvent(category: .push, name: "outboxDrained", severity: .info))
        #expect(monitor.status == .healthy)
        #expect(monitor.message == nil)
    }

    @MainActor
    @Test("each status exposes a non-empty label and an SF Symbol")
    func statusPresentationMetadata() {
        for status in [SyncStatus.healthy, .pending, .degraded] {
            #expect(!status.label.isEmpty)
            #expect(!status.symbolName.isEmpty)
        }
    }

    // MARK: - Transition telemetry (SHIFT-668)

    @MainActor
    @Test("status transitions fire the hook exactly once per change, with from/to")
    func transitionHookFiresOncePerChange() {
        final class Pending { var count = 0 }
        let pending = Pending()
        let center = SyncDiagnosticsCenter(
            defaults: .standard, storageKey: "test.transition.\(UUID().uuidString)", maxEvents: 50
        )
        var transitions: [(from: SyncStatus, to: SyncStatus)] = []
        let monitor = SyncStatusMonitor(
            diagnostics: center,
            pendingWriteCount: { pending.count },
            onTransition: { from, to in transitions.append((from, to)) }
        )

        // healthy → pending
        pending.count = 2
        monitor.refreshPending()
        // pending → degraded
        monitor.ingest(DiagnosticEvent(category: .push, name: "outboxEntryParked", severity: .error))
        // degraded → healthy
        pending.count = 0
        monitor.ingest(DiagnosticEvent(category: .push, name: "outboxDrained", severity: .info))

        #expect(transitions.count == 3)
        #expect(transitions[0].from == .healthy && transitions[0].to == .pending)
        #expect(transitions[1].from == .pending && transitions[1].to == .degraded)
        #expect(transitions[2].from == .degraded && transitions[2].to == .healthy)
    }

    @MainActor
    @Test("a refresh that doesn't change the status does not fire the hook")
    func noTransitionNoHook() {
        final class Pending { var count = 0 }
        let pending = Pending()
        let center = SyncDiagnosticsCenter(
            defaults: .standard, storageKey: "test.transition.\(UUID().uuidString)", maxEvents: 50
        )
        var fired = 0
        let monitor = SyncStatusMonitor(
            diagnostics: center,
            pendingWriteCount: { pending.count },
            onTransition: { _, _ in fired += 1 }
        )

        monitor.refreshPending()                 // healthy → healthy
        monitor.refreshPending()                 // still healthy
        pending.count = 3
        monitor.refreshPending()                 // healthy → pending (fires)
        pending.count = 4
        monitor.refreshPending()                 // pending → pending (silent)

        #expect(fired == 1)
    }
}
