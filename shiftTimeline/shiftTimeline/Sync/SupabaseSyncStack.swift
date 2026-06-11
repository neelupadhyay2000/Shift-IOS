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

/// The sync composition root: the single object that wires the
/// whole Supabase data layer together and owns its lifecycle. Built by the app
/// only when `FeatureFlags.supabaseSync` is on; when the flag is off it is never
/// created and the app runs fully local (the kill-switch).
///
/// It assembles the four halves of the sync engine:
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
    /// User-facing sync health: drives the `SyncStatusIndicator` and
    /// the surfaced error message. Injected into the environment by the app.
    let statusMonitor: SyncStatusMonitor

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

        // Centralized backoff/rate-limit tuning.
        let tuning = SyncTuning.default

        // Push: drain the Outbox to Supabase, recording each write so its realtime
        // echo is recognized and skipped. Built before the write path so the
        // scheduler can be the writes' flush trigger. Backoff is tuned + equal-
        // jittered so a fleet reconnecting after a shared outage spreads its
        // retries instead of stampeding Supabase.
        let flusher = OutboxFlusher(
            context: context,
            remote: SupabaseOutboxSender(client: client),
            diagnostics: diagnostics,
            echoSuppressor: suppressor,
            baseDelay: tuning.outboxBaseDelay,
            maxDelay: tuning.outboxMaxDelay,
            maxAttempts: tuning.outboxMaxAttempts,
            jitter: { OutboxFlusher.equalJitter($0, random: { Double.random(in: 0..<1) }) }
        )
        self.flusher = flusher
        // Capture the locals (not `self`) in the trigger closures — no retain cycle.
        let scheduler = FlushScheduler(interval: tuning.flushDebounceInterval) { await flusher.flush() }
        self.scheduler = scheduler
        connectivity = ConnectivityMonitor { scheduler.requestFlush() }

        // User-facing sync status: pending depth = the Outbox count;
        // errors fold in from the diagnostics funnel it observes. Status
        // *transitions* are forwarded to TelemetryDeck so degraded /
        // recovered sync health is observable in production — filter the
        // `syncHealthChanged` signal on `to == degraded` for alerting.
        let monitor = SyncStatusMonitor(
            diagnostics: diagnostics,
            pendingWriteCount: { (try? context.fetchCount(FetchDescriptor<OutboxEntry>())) ?? 0 },
            onTransition: { from, to in
                AnalyticsService.send(.syncHealthChanged, parameters: [
                    "from": from.rawValue,
                    "to": to.rawValue,
                ])
            }
        )
        statusMonitor = monitor

        // Writes: local SwiftData + Outbox enqueue (owner stamped from the session).
        // Each enqueue nudges the scheduler, so a write reaches Supabase within
        // seconds — not just on the next launch / sign-in / foreground / reconnect.
        // It also bumps the status monitor's pending count so the indicator
        // reflects the queued write immediately.
        repositoryProvider = OutboxRepositoryProvider(
            context: context,
            local: SwiftDataRepositoryProvider(context: context),
            currentOwnerID: currentOwnerID,
            diagnostics: diagnostics,
            onEnqueue: {
                scheduler.requestFlush()
                monitor.refreshPending()
            }
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
        await refresh()
    }

    /// Pull-to-refresh / on-demand sync: push pending writes, then re-hydrate the
    /// **full** accessible graph. A full hydrate (not a delta) is required so an
    /// event newly shared with this user — whose own `updated_at` may be old —
    /// still loads, which a `updated_at > watermark` delta would miss.
    func refresh() async {
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
