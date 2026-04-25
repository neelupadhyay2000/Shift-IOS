import Foundation
import Models
import Services
import SwiftData
import Testing

/// Tests for `PostEventReportGenerator` (Subtask 1 of the Post-Event Report user story).
///
/// The generator produces a `PostEventReport` from an `EventModel` once the
/// event status transitions to `.completed`. The report compares each block's
/// `originalStart` (planned) against `completedTime` (actual), computes a
/// per-block delta in minutes, sums total drift, and counts associated
/// `ShiftRecord`s.
///
/// Uncompleted blocks (cancelled / skipped) appear in the report with
/// `actualCompletion == nil` and contribute `0` to drift.
@Suite("PostEventReportGenerator")
struct PostEventReportGeneratorTests {

    // MARK: - Test Fixtures

    private let base = Date(timeIntervalSince1970: 1_750_000_000)

    /// Inserts an event with `count` blocks. Each block starts `count * 30 min`
    /// after `base`. Caller is responsible for marking blocks complete and
    /// inserting `ShiftRecord`s.
    @discardableResult
    private func makeEvent(
        in context: ModelContext,
        blockCount: Int = 3,
        status: EventStatus = .completed
    ) -> EventModel {
        let event = EventModel(
            title: "Test Wedding",
            date: base,
            latitude: 0,
            longitude: 0,
            status: status
        )
        context.insert(event)

        let track = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true)
        track.event = event
        context.insert(track)

        var blocks: [TimeBlockModel] = []
        for index in 0..<blockCount {
            let start = base.addingTimeInterval(TimeInterval(index) * 1800)
            let block = TimeBlockModel(
                title: "Block \(index)",
                scheduledStart: start,
                originalStart: start,
                duration: 1800
            )
            block.track = track
            context.insert(block)
            blocks.append(block)
        }
        return event
    }

    private func addShiftRecord(
        to event: EventModel,
        in context: ModelContext,
        deltaMinutes: Int = 5
    ) {
        let record = ShiftRecord(
            deltaMinutes: deltaMinutes,
            triggeredBy: .manual,
            event: event
        )
        context.insert(record)
    }

    private func sortedBlocks(for event: EventModel) -> [TimeBlockModel] {
        (event.tracks ?? [])
            .flatMap { $0.blocks ?? [] }
            .sorted { $0.scheduledStart < $1.scheduledStart }
    }

    // MARK: - Per-Block Entries

    @Test @MainActor
    func generateBuildsEntryPerBlockWithPlannedAndActualTimes() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let event = makeEvent(in: context, blockCount: 3)

        for block in sortedBlocks(for: event) {
            block.status = .completed
            block.completedTime = block.originalStart // exactly on time
        }

        let report = PostEventReportGenerator.generate(for: event)

        #expect(report.entries.count == 3)
        for (index, entry) in report.entries.enumerated() {
            #expect(entry.blockTitle == "Block \(index)")
            #expect(entry.plannedStart == base.addingTimeInterval(TimeInterval(index) * 1800))
            #expect(entry.actualCompletion == entry.plannedStart)
            #expect(entry.deltaMinutes == 0)
        }
    }

    @Test @MainActor
    func generateComputesPositiveDeltaForLateBlocks() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let event = makeEvent(in: context, blockCount: 1)

        let block = sortedBlocks(for: event)[0]
        block.status = .completed
        block.completedTime = block.originalStart.addingTimeInterval(15 * 60) // 15 min late

        let report = PostEventReportGenerator.generate(for: event)

        #expect(report.entries.first?.deltaMinutes == 15)
    }

    @Test @MainActor
    func generateComputesNegativeDeltaForEarlyBlocks() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let event = makeEvent(in: context, blockCount: 1)

        let block = sortedBlocks(for: event)[0]
        block.status = .completed
        block.completedTime = block.originalStart.addingTimeInterval(-7 * 60) // 7 min early

        let report = PostEventReportGenerator.generate(for: event)

        #expect(report.entries.first?.deltaMinutes == -7)
    }

    // MARK: - Uncompleted Blocks

    @Test @MainActor
    func generateExcludesUncompletedBlocksFromDriftButIncludesAsNilEntry() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let event = makeEvent(in: context, blockCount: 3)

        let blocks = sortedBlocks(for: event)
        // Block 0 completed late by 10 min.
        blocks[0].status = .completed
        blocks[0].completedTime = blocks[0].originalStart.addingTimeInterval(10 * 60)
        // Block 1 never completed (e.g. cancelled / skipped).
        blocks[1].status = .upcoming
        blocks[1].completedTime = nil
        // Block 2 completed late by 4 min.
        blocks[2].status = .completed
        blocks[2].completedTime = blocks[2].originalStart.addingTimeInterval(4 * 60)

        let report = PostEventReportGenerator.generate(for: event)

        #expect(report.entries.count == 3)
        #expect(report.entries[1].actualCompletion == nil)
        #expect(report.entries[1].deltaMinutes == 0)
        #expect(report.totalDriftMinutes == 14)
    }

    // MARK: - Totals

    @Test @MainActor
    func generateTotalDriftSumsCompletedBlockDeltasOnly() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let event = makeEvent(in: context, blockCount: 4)

        let deltas = [3, -2, 0, 8] // minutes
        for (index, block) in sortedBlocks(for: event).enumerated() {
            block.status = .completed
            block.completedTime = block.originalStart.addingTimeInterval(TimeInterval(deltas[index] * 60))
        }

        let report = PostEventReportGenerator.generate(for: event)

        #expect(report.totalDriftMinutes == 9)
    }

    @Test @MainActor
    func generateTotalShiftCountMatchesShiftRecordCount() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let event = makeEvent(in: context, blockCount: 2)

        for block in sortedBlocks(for: event) {
            block.status = .completed
            block.completedTime = block.originalStart
        }
        for _ in 0..<3 {
            addShiftRecord(to: event, in: context)
        }

        let report = PostEventReportGenerator.generate(for: event)

        #expect(report.totalShiftCount == 3)
    }

    // MARK: - Persistence

    @Test @MainActor
    func generatePersistsReportOnEventModelAccessibleAfterGeneration() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let event = makeEvent(in: context, blockCount: 2)

        for block in sortedBlocks(for: event) {
            block.status = .completed
            block.completedTime = block.originalStart.addingTimeInterval(60)
        }

        _ = PostEventReportGenerator.generate(for: event)

        let stored = event.postEventReport
        #expect(stored != nil)
        #expect(stored?.entries.count == 2)
        #expect(stored?.totalDriftMinutes == 2)
    }

    @Test @MainActor
    func generateIsIdempotentOverwritesPreviousReport() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let event = makeEvent(in: context, blockCount: 1)

        let block = sortedBlocks(for: event)[0]
        block.status = .completed
        block.completedTime = block.originalStart.addingTimeInterval(60) // 1 min late
        _ = PostEventReportGenerator.generate(for: event)
        #expect(event.postEventReport?.totalDriftMinutes == 1)

        // Update completion time and regenerate.
        block.completedTime = block.originalStart.addingTimeInterval(5 * 60) // 5 min late
        _ = PostEventReportGenerator.generate(for: event)

        #expect(event.postEventReport?.totalDriftMinutes == 5)
    }

    // MARK: - Acceptance Criteria

    @Test @MainActor
    func generateHandlesTenBlocksWithThreeShiftsWithoutErrors() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let event = makeEvent(in: context, blockCount: 10)

        var expectedDrift = 0
        for (index, block) in sortedBlocks(for: event).enumerated() {
            block.status = .completed
            let drift = (index % 4) - 1 // -1, 0, 1, 2, -1, 0, 1, 2, -1, 0
            block.completedTime = block.originalStart.addingTimeInterval(TimeInterval(drift * 60))
            expectedDrift += drift
        }
        addShiftRecord(to: event, in: context, deltaMinutes: 5)
        addShiftRecord(to: event, in: context, deltaMinutes: -3)
        addShiftRecord(to: event, in: context, deltaMinutes: 2)

        let report = PostEventReportGenerator.generate(for: event)

        #expect(report.entries.count == 10)
        #expect(report.totalDriftMinutes == expectedDrift)
        #expect(report.totalShiftCount == 3)
        #expect(event.postEventReport != nil)
    }
}
