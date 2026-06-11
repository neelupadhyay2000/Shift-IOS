import Foundation
import Testing
@testable import shiftTimeline

/// Covers the pure suggestion logic behind the Live Dashboard overtime nudge.
struct OvertimeNudgeTests {

    private let blockEnd = Date(timeIntervalSince1970: 1_750_000_000)

    @Test func noSuggestionWhileBlockIsOnTime() {
        let now = blockEnd.addingTimeInterval(-60)
        #expect(OvertimeNudge.suggestedMinutes(blockEnd: blockEnd, now: now) == nil)
    }

    @Test func noSuggestionBelowThreshold() {
        let now = blockEnd.addingTimeInterval(OvertimeNudge.threshold - 1)
        #expect(OvertimeNudge.suggestedMinutes(blockEnd: blockEnd, now: now) == nil)
    }

    @Test func suggestsFiveMinutesAtThreshold() {
        let now = blockEnd.addingTimeInterval(OvertimeNudge.threshold)
        #expect(OvertimeNudge.suggestedMinutes(blockEnd: blockEnd, now: now) == 5)
    }

    @Test func roundsUpToNextFiveMinutes() {
        // 7 minutes over → suggest +10, never less than the actual slippage.
        let now = blockEnd.addingTimeInterval(7 * 60)
        #expect(OvertimeNudge.suggestedMinutes(blockEnd: blockEnd, now: now) == 10)
    }

    @Test func exactMultipleStaysAtThatMultiple() {
        let now = blockEnd.addingTimeInterval(10 * 60)
        #expect(OvertimeNudge.suggestedMinutes(blockEnd: blockEnd, now: now) == 10)
    }

    @Test func largeOvertimeSuggestsProportionally() {
        let now = blockEnd.addingTimeInterval(23 * 60)
        #expect(OvertimeNudge.suggestedMinutes(blockEnd: blockEnd, now: now) == 25)
    }
}
