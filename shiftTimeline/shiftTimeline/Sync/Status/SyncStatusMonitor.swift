import Foundation
import Observation
import Services

/// Live, observable bridge from the sync engine to the UI. Drives the
/// ``SyncStatusIndicator`` and the surfaced error message.
///
/// It folds two signals into ``SyncHealth``:
/// - **pending writes** — the Outbox depth, recomputed via the injected
///   `pendingWriteCount` whenever a write is enqueued or the queue drains;
/// - **unresolved errors** — every ``DiagnosticEvent`` is observed from the
///   shared ``SyncDiagnosticsCenter`` and folded through ``SyncErrorState`` (an
///   `.error` degrades its stage; the next `.info` in that stage clears it).
///
/// `@Observable`, so any SwiftUI view that reads `status`/`message` re-renders on
/// change. The diagnostics observer fires off the main actor, so it hops back on
/// before mutating; the synchronous `ingest`/`refreshPending` are exposed for
/// deterministic testing.
@MainActor
@Observable
final class SyncStatusMonitor {

    private(set) var health: SyncHealth

    @ObservationIgnored private var errorState = SyncErrorState()
    @ObservationIgnored private let pendingWriteCount: @MainActor () -> Int
    /// Fired exactly once per status *change* (`from`, `to`) — never on a
    /// refresh that lands on the same status. The sync stack wires this to
    /// telemetry so production sync-health transitions are
    /// observable without polling.
    @ObservationIgnored private let onTransition: @MainActor (SyncStatus, SyncStatus) -> Void

    /// The current user-facing status.
    var status: SyncStatus { health.status }

    /// The message to surface, or `nil` when healthy.
    var message: String? {
        SyncStatusMessage.text(
            for: status,
            failingStage: errorState.primaryFailingStage,
            pendingWrites: health.pendingWrites
        )
    }

    init(
        diagnostics: SyncDiagnosticsCenter = .shared,
        pendingWriteCount: @escaping @MainActor () -> Int = { 0 },
        onTransition: @escaping @MainActor (SyncStatus, SyncStatus) -> Void = { _, _ in }
    ) {
        self.pendingWriteCount = pendingWriteCount
        self.onTransition = onTransition
        health = SyncHealth(pendingWrites: pendingWriteCount(), hasUnresolvedError: false)

        // Observe the funnel. The sink fires on the recording thread, so marshal
        // back to the main actor before touching observable state. Bind `self`
        // strongly here (the synchronous sink body) so the hop-to-main `Task`
        // captures an immutable `let` — referencing the outer `weak var self`
        // from the Task is a data race under Swift 6.
        diagnostics.addObserver { [weak self] event in
            guard let self else { return }
            Task { @MainActor in self.ingest(event) }
        }
    }

    /// Recomputes the pending-writes signal — call after an enqueue or a flush.
    func refreshPending() {
        updateHealth(
            SyncHealth(pendingWrites: pendingWriteCount(), hasUnresolvedError: errorState.hasUnresolvedError)
        )
    }

    /// Folds one diagnostic event into the error state and refreshes health.
    /// A drain (`outboxDrained`) both clears its stage and changes the queue
    /// depth, so pending is recomputed alongside.
    func ingest(_ event: DiagnosticEvent) {
        errorState.ingest(event)
        updateHealth(
            SyncHealth(pendingWrites: pendingWriteCount(), hasUnresolvedError: errorState.hasUnresolvedError)
        )
    }

    /// Applies the new health and fires the transition hook iff the derived
    /// status actually changed.
    private func updateHealth(_ newHealth: SyncHealth) {
        let previous = health.status
        health = newHealth
        let current = newHealth.status
        if previous != current {
            onTransition(previous, current)
        }
    }
}
