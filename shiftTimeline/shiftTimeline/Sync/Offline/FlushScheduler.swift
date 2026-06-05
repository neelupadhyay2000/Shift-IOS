import Foundation

/// Debounces flush triggers so a flurry of connectivity changes — walking in and
/// out of signal — collapses into a single flush instead of a reconnect storm.
///
/// Each ``requestFlush()`` restarts a debounce window; the flush runs once the
/// window elapses without another trigger, so an arbitrarily long burst of
/// reconnects produces exactly one flush. (Batching of the queue itself is
/// already handled by ``OutboxFlusher/flushOnce()``, which drains every pending
/// entry in one FIFO pass; this type only tames the *triggering*.)
///
/// Pair it with ``ConnectivityMonitor``; launch / sign-in should flush
/// immediately (`flusher.flush()`) — only the noisy connectivity trigger needs
/// debouncing:
/// ```swift
/// let scheduler = FlushScheduler { await flusher.flush() }
/// let connectivity = ConnectivityMonitor { scheduler.requestFlush() }
/// ```
/// The flusher's own single-flight guard then collapses any flush that still
/// overlaps an in-flight one.
@MainActor
final class FlushScheduler {
    private let interval: TimeInterval
    private let sleep: @Sendable (TimeInterval) async -> Void
    private let flush: @MainActor () async -> Void

    // private(set) so tests can await the pending flush; nonisolated(unsafe) so
    // the nonisolated `deinit` can cancel it.
    private(set) nonisolated(unsafe) var pendingTask: Task<Void, Never>?

    init(
        interval: TimeInterval = 2,
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) },
        flush: @escaping @MainActor () async -> Void
    ) {
        self.interval = interval
        self.sleep = sleep
        self.flush = flush
    }

    /// Requests a flush, coalescing with any trigger still inside the debounce
    /// window — the prior pending flush is cancelled and the window restarts.
    func requestFlush() {
        pendingTask?.cancel()
        let interval = self.interval
        // @MainActor so the body is serialized after the (main-actor) burst that
        // schedules and cancels it — a prior trigger is always cancelled before
        // its task can run. `await sleep` still suspends rather than blocking main.
        pendingTask = Task { @MainActor [sleep, flush] in
            await sleep(interval)
            guard !Task.isCancelled else { return }
            await flush()
        }
    }

    /// Cancels any pending debounced flush (e.g. on teardown).
    func cancel() {
        pendingTask?.cancel()
        pendingTask = nil
    }

    deinit {
        pendingTask?.cancel()
    }
}
