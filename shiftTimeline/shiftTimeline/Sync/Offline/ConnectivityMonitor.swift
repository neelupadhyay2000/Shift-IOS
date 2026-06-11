import Foundation
import Network

/// Observes network reachability with `NWPathMonitor` and drives an Outbox flush
/// whenever connectivity is *regained*.
///
/// The exposed signal is ``isOnline`` (the latest reachability sample) plus the
/// injected ``onReconnect`` trigger, which fires **only on an offline → online
/// transition** — never while merely staying online, and never on going offline.
/// That keeps the flush tied to the one moment it matters (the queue can finally
/// drain) and avoids redundant flushes. Launch-time draining is the flush
/// engine's own concern, so a first "online" sample at startup is a
/// no-op here.
///
/// Wiring (the cutover, not this subtask):
/// ```swift
/// let connectivity = ConnectivityMonitor { Task { await syncEngine.flush() } }
/// connectivity.start()
/// ```
///
/// `NWPathMonitor` delivers updates on a background queue; every sample is
/// funnelled to the main actor through ``pathDidUpdate(isOnline:)``, which is
/// also the seam unit tests drive directly (no real radio required).
@MainActor
final class ConnectivityMonitor {
    /// The most recent reachability sample. Optimistically `true` until the first
    /// path update corrects it, so a genuine first-online sample isn't mistaken
    /// for a reconnect.
    private(set) var isOnline: Bool

    private let onReconnect: @MainActor () -> Void
    private let monitorQueue = DispatchQueue(label: "com.shift.sync.connectivity")

    // nonisolated(unsafe) so the nonisolated `deinit` can cancel it; `NWPathMonitor`
    // is safe to cancel from any thread and every other access is on the main
    // actor (matches `RealtimeLifecycleManager`'s `streamTask` pattern).
    private nonisolated(unsafe) var monitor: NWPathMonitor?

    init(isOnline: Bool = true, onReconnect: @escaping @MainActor () -> Void) {
        self.isOnline = isOnline
        self.onReconnect = onReconnect
    }

    /// Begins system observation. Idempotent — a second call while already
    /// observing is a no-op.
    func start() {
        guard monitor == nil else { return }
        let pathMonitor = NWPathMonitor()
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            guard let self else { return }
            Task { @MainActor in self.pathDidUpdate(isOnline: online) }
        }
        pathMonitor.start(queue: monitorQueue)
        monitor = pathMonitor
    }

    /// Stops system observation and releases the monitor.
    func stop() {
        monitor?.cancel()
        monitor = nil
    }

    /// Applies one reachability sample. The single funnel the system path handler
    /// routes through, and the test seam. Fires ``onReconnect`` only when the
    /// state flips from offline to online.
    func pathDidUpdate(isOnline newValue: Bool) {
        let wasOnline = isOnline
        isOnline = newValue
        if newValue, !wasOnline {
            onReconnect()
        }
    }

    deinit {
        monitor?.cancel()
    }
}
