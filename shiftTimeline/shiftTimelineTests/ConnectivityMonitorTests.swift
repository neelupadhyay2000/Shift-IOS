import Foundation
@testable import shiftTimeline
import Testing

/// SHIFT-610: connectivity is observed and a return to online drives the flush.
/// The `NWPathMonitor` plumbing is thin glue exercised at runtime; the
/// transition logic — which is what the acceptance criteria turns on — is driven
/// here through the `pathDidUpdate(isOnline:)` seam.
@Suite("Connectivity monitor")
@MainActor
struct ConnectivityMonitorTests {

    /// Counts how many times the reconnect trigger fired.
    private final class FlushRecorder {
        var count = 0
    }

    @Test("offline → online drives exactly one flush")
    func reconnectTriggersFlush() {
        let recorder = FlushRecorder()
        let monitor = ConnectivityMonitor(isOnline: true) { recorder.count += 1 }

        monitor.pathDidUpdate(isOnline: false) // drop offline
        monitor.pathDidUpdate(isOnline: true)  // return online → flush

        #expect(recorder.count == 1)
        #expect(monitor.isOnline)
    }

    @Test("staying online never re-triggers a flush")
    func noFlushWhileStayingOnline() {
        let recorder = FlushRecorder()
        let monitor = ConnectivityMonitor(isOnline: true) { recorder.count += 1 }

        monitor.pathDidUpdate(isOnline: true)
        monitor.pathDidUpdate(isOnline: true)

        #expect(recorder.count == 0)
        #expect(monitor.isOnline)
    }

    @Test("going offline does not trigger a flush")
    func noFlushOnGoingOffline() {
        let recorder = FlushRecorder()
        let monitor = ConnectivityMonitor(isOnline: true) { recorder.count += 1 }

        monitor.pathDidUpdate(isOnline: false)

        #expect(recorder.count == 0)
        #expect(!monitor.isOnline)
    }

    @Test("every reconnect drives a fresh flush")
    func repeatedReconnectsEachFlush() {
        let recorder = FlushRecorder()
        let monitor = ConnectivityMonitor(isOnline: true) { recorder.count += 1 }

        monitor.pathDidUpdate(isOnline: false)
        monitor.pathDidUpdate(isOnline: true)  // +1
        monitor.pathDidUpdate(isOnline: false)
        monitor.pathDidUpdate(isOnline: true)  // +1

        #expect(recorder.count == 2)
    }

    @Test("launching offline, the first online sample drives one flush")
    func startingOfflineFlushesOnFirstOnline() {
        let recorder = FlushRecorder()
        let monitor = ConnectivityMonitor(isOnline: false) { recorder.count += 1 }

        monitor.pathDidUpdate(isOnline: true) // offline → online

        #expect(recorder.count == 1)
        #expect(monitor.isOnline)
    }

    @Test("launching online, a first online sample is a no-op (no spurious flush)")
    func startingOnlineDoesNotFlushOnFirstSample() {
        let recorder = FlushRecorder()
        let monitor = ConnectivityMonitor(isOnline: true) { recorder.count += 1 }

        monitor.pathDidUpdate(isOnline: true)

        #expect(recorder.count == 0)
    }
}
