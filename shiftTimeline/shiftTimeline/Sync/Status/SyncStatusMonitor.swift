import Foundation
import Observation
import Services

/// Live, observable bridge from the sync engine to the UI (SHIFT-664). Drives the
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
        pendingWriteCount: @escaping @MainActor () -> Int = { 0 }
    ) {
        self.pendingWriteCount = pendingWriteCount
        health = SyncHealth(pendingWrites: pendingWriteCount(), hasUnresolvedError: false)

        // Observe the funnel. The sink fires on the recording thread, so marshal
        // back to the main actor before touching observable state.
        diagnostics.addObserver { [weak self] event in
            Task { @MainActor in self?.ingest(event) }
        }
    }

    /// Recomputes the pending-writes signal — call after an enqueue or a flush.
    func refreshPending() {
        health = SyncHealth(
            pendingWrites: pendingWriteCount(),
            hasUnresolvedError: errorState.hasUnresolvedError
        )
    }

    /// Folds one diagnostic event into the error state and refreshes health.
    /// A drain (`outboxDrained`) both clears its stage and changes the queue
    /// depth, so pending is recomputed alongside.
    func ingest(_ event: DiagnosticEvent) {
        errorState.ingest(event)
        health = SyncHealth(
            pendingWrites: pendingWriteCount(),
            hasUnresolvedError: errorState.hasUnresolvedError
        )
    }
}
