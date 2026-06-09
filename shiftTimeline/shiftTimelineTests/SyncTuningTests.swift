import Foundation
@testable import shiftTimeline
import Testing

/// SHIFT-663 — the tuned backoff/rate-limit policy is centralized in
/// ``SyncTuning``. These pin the defaults (so a careless edit is caught) and
/// confirm the flusher's backoff honours the tuned cap.
@Suite("Sync tuning (SHIFT-663)")
struct SyncTuningTests {

    @Test("the tuned defaults match the documented rate-limit policy")
    func tunedDefaults() {
        let tuning = SyncTuning.default
        #expect(tuning.outboxBaseDelay == 1)
        #expect(tuning.outboxMaxDelay == 30)   // tuned down from the flusher's 60s default
        #expect(tuning.outboxMaxAttempts == 8)
        #expect(tuning.flushDebounceInterval == 2)
    }

    @Test("backoff doubles under the tuned cap and is bounded by it")
    func backoffRespectsTunedCap() {
        let tuning = SyncTuning.default
        // attempt 3 → 4s (un-capped); attempt 6 → 32s un-capped, held at the 30s cap.
        #expect(OutboxFlusher.backoffSeconds(forAttempt: 3, base: tuning.outboxBaseDelay, cap: tuning.outboxMaxDelay) == 4)
        #expect(OutboxFlusher.backoffSeconds(forAttempt: 6, base: tuning.outboxBaseDelay, cap: tuning.outboxMaxDelay) == 30)
    }
}
