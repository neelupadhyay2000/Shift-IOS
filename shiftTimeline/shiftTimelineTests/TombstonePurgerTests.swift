import Foundation
@testable import shiftTimeline
import Testing

/// SHIFT-618: the purge cutoff. The actual table-reaping `purge(now:)` hits
/// Supabase (online acceptance); the retention math is verified here.
@Suite("Tombstone purger")
struct TombstonePurgerTests {

    @Test("the cutoff is exactly one retention window before now, and in the past")
    func cutoffIsRetentionBeforeNow() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let retention: TimeInterval = 30 * 24 * 60 * 60 // 30 days

        let cutoff = TombstonePurger.cutoffDate(now: now, retention: retention)

        #expect(cutoff == now.addingTimeInterval(-retention))
        #expect(cutoff < now)
    }
}
