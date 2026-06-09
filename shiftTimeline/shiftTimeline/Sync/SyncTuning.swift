import Foundation

/// Centralized sync tuning knobs (SHIFT-663) — the single place backoff, retry,
/// and debounce are set, so the rate-limit behavior is reasoned about as a whole
/// rather than as magic numbers scattered across `OutboxFlusher` and
/// `FlushScheduler`. `SupabaseSyncStack` constructs both from `SyncTuning.default`.
///
/// Defaults are tuned for SHIFT's workload:
/// - **`outboxBaseDelay` 1s / `outboxMaxDelay` 30s:** a planner who walks back
///   into signal mid-event should resync within seconds, so the first retry is
///   quick; the 30s cap (down from the flusher's conservative 60s) keeps a
///   throttled or poison write from waiting a full minute between attempts while
///   still backing off hard enough to be server-friendly. Paired with equal
///   jitter in the flusher so a fleet reconnecting after a shared outage spreads
///   its retries instead of stampeding Supabase.
/// - **`outboxMaxAttempts` 8:** ~enough doublings to ride out a multi-minute
///   outage, after which an entry parks (surfaced via diagnostics) so one bad
///   write can't head-of-line-block the rest of the queue forever.
/// - **`flushDebounceInterval` 2s:** collapses a burst of connectivity flaps
///   (walking in/out of signal) into a single flush.
struct SyncTuning: Sendable, Equatable {
    /// First-retry delay; doubles each attempt up to `outboxMaxDelay`.
    var outboxBaseDelay: TimeInterval
    /// Exponential-backoff ceiling — a single throttled/poison write never waits
    /// longer than this between attempts.
    var outboxMaxDelay: TimeInterval
    /// Failed sends before an entry is parked so it can't block the queue.
    var outboxMaxAttempts: Int
    /// Debounce window collapsing a burst of reconnect triggers into one flush.
    var flushDebounceInterval: TimeInterval

    static let `default` = SyncTuning(
        outboxBaseDelay: 1,
        outboxMaxDelay: 30,
        outboxMaxAttempts: 8,
        flushDebounceInterval: 2
    )
}
