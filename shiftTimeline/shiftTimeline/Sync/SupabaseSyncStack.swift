import Foundation
import Models
import Services
import Supabase
import SwiftData

/// Run after a Supabase session is established (sign-in *or* restore) — the hook
/// the auth service calls so the sync stack can pull the user's graph and drain
/// pending writes. Abstracted so `SupabaseAuthService` doesn't depend on the
/// concrete stack and tests can omit it.
@MainActor
protocol SessionSyncing {
    func onSessionEstablished() async
}

/// The E16 cutover composition root (SHIFT-658): the single object that wires the
/// whole Supabase data layer together and owns its lifecycle. Built by the app
/// only when `FeatureFlags.supabaseSync` is on; when the flag is off it is never
/// created and the app runs fully local (the kill-switch).
///
/// It assembles the four halves that were built across E12–E13 but never wired:
/// - **Writes** — `repositoryProvider` (Outbox): every timeline mutation writes
///   local-first and enqueues an `OutboxEntry`. Injected at the scene root, so
///   all existing repository call sites flip onto it.
/// - **Push** — `OutboxFlusher` drains the queue to Supabase FIFO, driven by
///   `ConnectivityMonitor` → `FlushScheduler` (debounced) plus explicit flushes
///   on launch / sign-in / foreground.
/// - **Pull** — `InitialHydrator` reconstructs the local cache on session
///   establishment; `DeltaReconciler` catches up the foreground delta.
/// - **Echo** — one shared `RealtimeEchoSuppressor` records every pushed write
///   and is handed to the realtime applier (here and, via the environment, to
///   `EventDetailView`) so a device's own writes aren't re-applied.
@MainActor
@Observable
final class SupabaseSyncStack: SessionSyncing {
    /// Inject at the scene root via `.repositories(_:)` — routes all writes
    /// through the Outbox.
    let repositoryProvider: OutboxRepositoryProvider
    /// Shared with the realtime applier (via the environment) so self-writes are
    /// recognized as echoes and skipped.
    let echoSuppressor: RealtimeEchoSuppressor

    @ObservationIgnored private let flusher: OutboxFlusher
    @ObservationIgnored private let scheduler: FlushScheduler
    @ObservationIgnored private let connectivity: ConnectivityMonitor
    @ObservationIgnored private let hydrator: InitialHydrator
    @ObservationIgnored private let delta: DeltaReconciler
    @ObservationIgnored private let diagnostics: SyncDiagnosticsCenter

    init(
        client: SupabaseClient,
        context: ModelContext,
        currentOwnerID: @escaping @MainActor () -> UUID?,
        watermarks: LastPulledStore = LastPulledStore(),
        diagnostics: SyncDiagnosticsCenter = .shared
    ) {
        self.diagnostics = diagnostics

        let suppressor = RealtimeEchoSuppressor()
        echoSuppressor = suppressor

        // Push: drain the Outbox to Supabase, recording each write so its realtime
        // echo is recognized and skipped. Built before the write path so the
        // scheduler can be the writes' flush trigger.
        let flusher = OutboxFlusher(
            context: context,
            remote: SupabaseOutboxSender(client: client),
            diagnostics: diagnostics,
            echoSuppressor: suppressor
        )
        self.flusher = flusher
        // Capture the locals (not `self`) in the trigger closures — no retain cycle.
        let scheduler = FlushScheduler { await flusher.flush() }
        self.scheduler = scheduler
        connectivity = ConnectivityMonitor { scheduler.requestFlush() }

        // Writes: local SwiftData + Outbox enqueue (owner stamped from the session).
        // Each enqueue nudges the scheduler, so a write reaches Supabase within
        // seconds — not just on the next launch / sign-in / foreground / reconnect.
        repositoryProvider = OutboxRepositoryProvider(
            context: context,
            local: SwiftDataRepositoryProvider(context: context),
            currentOwnerID: currentOwnerID,
            diagnostics: diagnostics,
            onEnqueue: { scheduler.requestFlush() }
        )

        // Pull: full hydration on session establishment; foreground delta catch-up.
        hydrator = InitialHydrator(
            source: SupabaseHydrationSource(client: client),
            context: context,
            diagnostics: diagnostics
        )
        delta = DeltaReconciler(
            source: SupabaseDeltaSource(client: client),
            applier: RealtimeChangeApplier(context: context, echoSuppressor: suppressor),
            watermarks: watermarks,
            diagnostics: diagnostics
        )
    }

    // MARK: - Lifecycle

    /// Begins connectivity-driven flushing and drains anything already queued
    /// (e.g. writes made before this launch, or the backfill). Call once at launch.
    func start() {
        connectivity.start()
        Task { await flusher.flush() }
    }

    /// On session establishment: **push then pull**. Drain the Outbox first so
    /// writes made while signed-out — or the one-time backfill enqueued moments
    /// earlier — reach Supabase, then hydrate the local cache from the now-current
    /// remote. Best-effort: a failed hydrate is recorded by the hydrator and
    /// realtime/delta still converge.
    func onSessionEstablished() async {
        await flusher.flush()
        try? await hydrator.hydrate()
    }

    /// On foreground: pull the delta missed while realtime was disconnected, then
    /// push pending writes. Best-effort — the reconciler records its own errors.
    func reconcileOnForeground() async {
        try? await delta.reconcile()
        await flusher.flush()
    }
}
