import Foundation

/// Pure suggestion logic behind the Live Dashboard's "running behind" nudge.
///
/// Once the active block has run `threshold` past its scheduled end, the
/// dashboard surfaces a one-tap path into the quick-shift flow — putting the
/// shift feature in the user's hand at the exact moment they need it.
nonisolated enum OvertimeNudge {

    /// Overtime grace period before the nudge appears. Short delays self-resolve;
    /// nudging at 30 seconds over would just be noise.
    static let threshold: TimeInterval = 180

    /// Suggested shift in minutes (multiples of 5, covering at least the actual
    /// slippage), or `nil` while the block is on time / within the grace period.
    static func suggestedMinutes(
        blockEnd: Date,
        now: Date,
        threshold: TimeInterval = threshold
    ) -> Int? {
        let overtime = now.timeIntervalSince(blockEnd)
        guard overtime >= threshold else { return nil }
        let overtimeMinutes = overtime / 60
        let roundedToFive = Int((overtimeMinutes / 5).rounded(.up)) * 5
        return max(5, roundedToFive)
    }
}
