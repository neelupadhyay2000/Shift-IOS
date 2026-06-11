import Foundation
@testable import shiftTimeline
import Testing

/// A burst of reconnect triggers must be debounced into a single
/// flush, not one per trigger. The debounce window's `sleep` is injected so the
/// tests are deterministic — the burst is applied synchronously (cancelling the
/// prior pending flush) before any task body runs.
@Suite("Flush scheduler (debounce)")
@MainActor
struct FlushSchedulerTests {

    /// Counts how many times the debounced flush actually ran.
    @MainActor
    final class FlushCounter {
        private(set) var count = 0
        func increment() { count += 1 }
    }

    @Test("a single request flushes once")
    func singleRequestFlushesOnce() async {
        let counter = FlushCounter()
        let scheduler = FlushScheduler(interval: 0, sleep: { _ in }, flush: { counter.increment() })

        scheduler.requestFlush()
        await scheduler.pendingTask?.value

        #expect(counter.count == 1)
    }

    @Test("a burst of requests coalesces into a single flush")
    func burstCoalescesToSingleFlush() async {
        let counter = FlushCounter()
        let scheduler = FlushScheduler(interval: 0, sleep: { _ in }, flush: { counter.increment() })

        // Applied synchronously: each call cancels the prior pending flush before
        // any task body runs, so only the last survives.
        scheduler.requestFlush()
        scheduler.requestFlush()
        scheduler.requestFlush()
        await scheduler.pendingTask?.value

        #expect(counter.count == 1)
    }

    @Test("cancel drops a pending flush")
    func cancelPreventsPendingFlush() async {
        let counter = FlushCounter()
        let scheduler = FlushScheduler(interval: 0, sleep: { _ in }, flush: { counter.increment() })

        scheduler.requestFlush()
        let pending = scheduler.pendingTask
        scheduler.cancel()
        await pending?.value // the cancelled task runs but must not flush

        #expect(counter.count == 0)
        #expect(scheduler.pendingTask == nil)
    }

    @Test("separated requests each flush (debounce isn't one-shot)")
    func sequentialRequestsEachFlush() async {
        let counter = FlushCounter()
        let scheduler = FlushScheduler(interval: 0, sleep: { _ in }, flush: { counter.increment() })

        scheduler.requestFlush()
        await scheduler.pendingTask?.value
        scheduler.requestFlush()
        await scheduler.pendingTask?.value

        #expect(counter.count == 2)
    }
}
