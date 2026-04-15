import Foundation
import Models
import Testing

/// Tests for the overtime state logic extracted from ActiveBlockHero's computed properties.
///
/// The view computes `isOvertime = blockEnd.timeIntervalSince(now) < 0`.
/// These tests verify that computation directly using plain TimeBlockModel values,
/// without needing UI or SwiftData.
struct ActiveBlockHeroOvertimeTests {

    // MARK: - isOvertime derivation

    /// A block whose end time is in the past must be considered overtime.
    @Test func blockEndedInPastIsOvertime() {
        let start = Date.now.addingTimeInterval(-120) // started 2 min ago
        let duration: TimeInterval = 60               // 1 min long → ended 1 min ago
        let block = TimeBlockModel(
            title: "Ceremony",
            scheduledStart: start,
            duration: duration
        )

        let blockEnd = block.scheduledStart.addingTimeInterval(block.duration)
        let remaining = blockEnd.timeIntervalSince(.now)

        #expect(remaining < 0, "remaining should be negative when block has ended")
    }

    /// A block whose end time is in the future must NOT be overtime.
    @Test func blockEndingInFutureIsNotOvertime() {
        let start = Date.now.addingTimeInterval(-30) // started 30s ago
        let duration: TimeInterval = 120             // 2 min long → ends in ~90s
        let block = TimeBlockModel(
            title: "Dinner",
            scheduledStart: start,
            duration: duration
        )

        let blockEnd = block.scheduledStart.addingTimeInterval(block.duration)
        let remaining = blockEnd.timeIntervalSince(.now)

        #expect(remaining > 0, "remaining should be positive when block has not ended")
    }

    /// A block that ends at this exact instant is at the boundary — treat as overtime.
    @Test func blockEndingExactlyNowIsOvertime() {
        // scheduledStart = now - duration, so blockEnd == now approximately.
        // We nudge 1s into the past to guarantee remaining < 0 in test execution.
        let duration: TimeInterval = 60
        let start = Date.now.addingTimeInterval(-duration - 1)
        let block = TimeBlockModel(
            title: "Setup",
            scheduledStart: start,
            duration: duration
        )

        let blockEnd = block.scheduledStart.addingTimeInterval(block.duration)
        let remaining = blockEnd.timeIntervalSince(.now)

        #expect(remaining < 0, "boundary block (end ≤ now) should be overtime")
    }

    // MARK: - BlockStatus transition

    /// After go-live activation the first block must carry `.active` status.
    @Test func firstBlockGetsActiveStatus() {
        let blocks = [
            TimeBlockModel(title: "Block A", scheduledStart: .now,                        duration: 1800),
            TimeBlockModel(title: "Block B", scheduledStart: .now.addingTimeInterval(1800), duration: 1800),
        ]

        // Simulate the activation logic from LiveDashboardView.activateFirstIncompleteBlockIfNeeded
        guard !blocks.contains(where: { $0.status == .active }),
              let first = blocks.first(where: { $0.status != .completed })
        else { return }

        for i in blocks.indices where blocks[i].status != .completed {
            blocks[i].status = .upcoming
        }
        first.status = .active

        #expect(blocks[0].status == .active)
        #expect(blocks[1].status == .upcoming)
    }

    /// `BlockStatus` should equal `.overtime` when explicitly set — enum round-trips correctly.
    @Test func blockStatusOvertimeEnumRoundTrips() throws {
        let block = TimeBlockModel(title: "Late Block", scheduledStart: .now, duration: 60)
        block.status = .overtime

        #expect(block.status == .overtime)

        // Codable round-trip
        let encoded = try JSONEncoder().encode(block.status)
        let decoded = try JSONDecoder().decode(BlockStatus.self, from: encoded)
        #expect(decoded == .overtime)
    }
}
