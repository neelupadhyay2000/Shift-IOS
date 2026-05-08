import Foundation
import Models

/// Generates a `PostEventReport` from a completed `EventModel`. Idempotent — re-calling replaces the stored report.
public enum PostEventReportGenerator {

    /// Builds report and writes it to `event.postEventReport`. `now` is injectable for deterministic tests.
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
            // Round to nearest whole minute to suppress sub-second noise.
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
