import Foundation
import Models

/// Generates a `PostEventReport` from a completed `EventModel`.
///
/// The generator compares each block's `originalStart` (the planned start
/// time before any shifts were applied) against `completedTime` (the
/// wall-clock moment the block was marked `.completed`), computes a
/// per-block delta in whole minutes, sums total timeline drift across
/// completed blocks, and counts the number of `ShiftRecord`s the engine
/// stamped during execution.
///
/// Blocks that were never completed (cancelled, skipped, or left over
/// when the event was forced to `.completed`) appear in the report with
/// `actualCompletion == nil` and contribute `0` to drift — they are
/// surfaced in the PDF as "—" rows so the planner can see what dropped.
///
/// Generation is idempotent: calling `generate(for:)` again replaces the
/// previously stored report on `event.postEventReport`.
public enum PostEventReportGenerator {

    /// Builds the report and writes it to `event.postEventReport`.
    ///
    /// - Parameters:
    ///   - event: The event to summarise. Should have `status == .completed`,
    ///     but the function does not enforce that — callers may want to
    ///     preview the report before transitioning the event status.
    ///   - now: Stamp for `PostEventReport.generatedAt`. Injected for
    ///     deterministic testing; defaults to `Date()`.
    /// - Returns: The freshly built report (also persisted on `event`).
    @discardableResult
    public static func generate(
        for event: EventModel,
        now: Date = Date()
    ) -> PostEventReport {
        let blocks = sortedBlocks(for: event)

        let entries = blocks.map(buildEntry(for:))

        let totalDrift = entries.reduce(0) { partial, entry in
            partial + (entry.actualCompletion == nil ? 0 : entry.deltaMinutes)
        }

        let report = PostEventReport(
            entries: entries,
            totalDriftMinutes: totalDrift,
            totalShiftCount: (event.shiftRecords ?? []).count,
            generatedAt: now
        )

        event.postEventReport = report
        return report
    }

    // MARK: - Private

    private static func sortedBlocks(for event: EventModel) -> [TimeBlockModel] {
        (event.tracks ?? [])
            .flatMap { $0.blocks ?? [] }
            .sorted { $0.scheduledStart < $1.scheduledStart }
    }

    private static func buildEntry(for block: TimeBlockModel) -> BlockReportEntry {
        let actual = block.completedTime
        let delta: Int = {
            guard let actual else { return 0 }
            // Round to nearest whole minute to keep the report stable
            // against sub-second timestamp noise.
            let seconds = actual.timeIntervalSince(block.originalStart)
            return Int((seconds / 60.0).rounded())
        }()

        return BlockReportEntry(
            blockID: block.id,
            blockTitle: block.title,
            plannedStart: block.originalStart,
            actualCompletion: actual,
            deltaMinutes: delta
        )
    }
}
