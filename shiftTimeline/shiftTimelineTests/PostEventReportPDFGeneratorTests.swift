#if os(iOS)
import Foundation
import Models
import Services
import Testing
import PDFKit

/// Tests for `PostEventReportPDFGenerator` (Subtask 2 of the Post-Event
/// Report user story).
///
/// The generator turns a `PostEventReport` + its parent `EventModel` into a
/// shareable PDF document. We verify three orthogonal concerns:
///   * Data correctness — the row model fed into the renderer reflects the
///     report exactly (titles, formatted times, deltas, totals).
///   * Filename contract — `SHIFT_Report_[EventName]_[Date].pdf`, sanitised
///     for filesystem safety.
///   * Output integrity — `generate(...)` returns a non-empty `Data` blob
///     that PDFKit can parse on a US Letter / A4 sized page.
@Suite("PostEventReportPDFGenerator")
struct PostEventReportPDFGeneratorTests {

    private let generator = PostEventReportPDFGenerator()

    // MARK: - Fixtures

    private let baseDate = Date(timeIntervalSince1970: 1_750_000_000)

    private func makeReport(entries: [BlockReportEntry], shifts: Int) -> PostEventReport {
        let drift = entries.reduce(0) { $0 + ($1.actualCompletion == nil ? 0 : $1.deltaMinutes) }
        return PostEventReport(
            entries: entries,
            totalDriftMinutes: drift,
            totalShiftCount: shifts,
            generatedAt: baseDate
        )
    }

    private func makeEvent(title: String = "Test Wedding") -> EventModel {
        EventModel(
            title: title,
            date: baseDate,
            latitude: 0,
            longitude: 0,
            status: .completed
        )
    }

    // MARK: - Row Model

    @Test @MainActor func buildRowsMirrorsEntriesInOrder() {
        let entries = [
            BlockReportEntry(
                blockID: UUID(),
                blockTitle: "Ceremony",
                plannedStart: baseDate,
                actualCompletion: baseDate.addingTimeInterval(180), // +3 min
                deltaMinutes: 3
            ),
            BlockReportEntry(
                blockID: UUID(),
                blockTitle: "Cocktails",
                plannedStart: baseDate.addingTimeInterval(3600),
                actualCompletion: baseDate.addingTimeInterval(3600 - 120), // -2 min
                deltaMinutes: -2
            ),
        ]
        let report = makeReport(entries: entries, shifts: 1)

        let rows = generator.buildRows(report: report)

        #expect(rows.count == 2)
        #expect(rows[0].title == "Ceremony")
        #expect(rows[0].deltaMinutes == 3)
        #expect(rows[0].deltaTone == .late)
        #expect(rows[1].title == "Cocktails")
        #expect(rows[1].deltaMinutes == -2)
        #expect(rows[1].deltaTone == .early)
    }

    @Test @MainActor func buildRowsTagsZeroDeltaAsOnTime() {
        let entry = BlockReportEntry(
            blockID: UUID(),
            blockTitle: "Toast",
            plannedStart: baseDate,
            actualCompletion: baseDate,
            deltaMinutes: 0
        )
        let rows = generator.buildRows(report: makeReport(entries: [entry], shifts: 0))

        #expect(rows.first?.deltaTone == .onTime)
    }

    @Test @MainActor func buildRowsRendersUncompletedBlocksWithEmDashAndNeutralTone() {
        let entry = BlockReportEntry(
            blockID: UUID(),
            blockTitle: "Cancelled Block",
            plannedStart: baseDate,
            actualCompletion: nil,
            deltaMinutes: 0
        )
        let rows = generator.buildRows(report: makeReport(entries: [entry], shifts: 0))

        #expect(rows.first?.actualCompletionDisplay == "—")
        #expect(rows.first?.deltaDisplay == "—")
        #expect(rows.first?.deltaTone == .neutral)
    }

    // MARK: - Summary Line

    @Test @MainActor func summaryLineFormatsPositiveDriftAndShiftCount() {
        let report = makeReport(
            entries: [
                BlockReportEntry(
                    blockID: UUID(),
                    blockTitle: "X",
                    plannedStart: baseDate,
                    actualCompletion: baseDate.addingTimeInterval(720),
                    deltaMinutes: 12
                ),
            ],
            shifts: 4
        )

        let summary = generator.summaryLine(for: report)

        #expect(summary.contains("+12"))
        #expect(summary.contains("4"))
    }

    @Test @MainActor func summaryLineFormatsNegativeDriftWithMinusSign() {
        let report = makeReport(
            entries: [
                BlockReportEntry(
                    blockID: UUID(),
                    blockTitle: "X",
                    plannedStart: baseDate,
                    actualCompletion: baseDate.addingTimeInterval(-300),
                    deltaMinutes: -5
                ),
            ],
            shifts: 1
        )

        let summary = generator.summaryLine(for: report)

        #expect(summary.contains("-5") || summary.contains("−5"))
    }

    // MARK: - Filename Contract

    @Test @MainActor func fileNameFollowsContractFormat() {
        let event = makeEvent(title: "Smith Wedding")
        let name = generator.fileName(for: event)

        #expect(name.hasPrefix("SHIFT_Report_"))
        #expect(name.hasSuffix(".pdf"))
        #expect(name.contains("Smith_Wedding") || name.contains("SmithWedding"))
    }

    @Test @MainActor func fileNameSanitisesFileSystemUnsafeCharacters() {
        let event = makeEvent(title: "John & Jane / 2026")
        let name = generator.fileName(for: event)

        // No reserved or shell-hostile characters.
        for forbidden: Character in ["/", "\\", ":", "&"] {
            #expect(!name.contains(forbidden), "Filename must not contain `\(forbidden)`: \(name)")
        }
        #expect(name.hasSuffix(".pdf"))
    }

    // MARK: - PDF Output

    @Test @MainActor func generateReturnsNonEmptyParseablePDFData() {
        let event = makeEvent()
        let entries = (0..<3).map { index in
            BlockReportEntry(
                blockID: UUID(),
                blockTitle: "Block \(index)",
                plannedStart: baseDate.addingTimeInterval(TimeInterval(index) * 1800),
                actualCompletion: baseDate.addingTimeInterval(TimeInterval(index) * 1800 + 60),
                deltaMinutes: 1
            )
        }
        let report = makeReport(entries: entries, shifts: 2)

        let data = generator.generate(report: report, event: event)

        #expect(data.count > 0)
        #expect(PDFDocument(data: data) != nil)
    }

    /// Acceptance: report with at least 10 blocks and multiple shifts must
    /// render to a valid multi-row PDF without overflowing the page.
    @Test @MainActor func generateRendersTenBlockReportWithoutErrors() {
        let event = makeEvent(title: "Big Event")
        let entries = (0..<12).map { index in
            BlockReportEntry(
                blockID: UUID(),
                blockTitle: "Block \(index)",
                plannedStart: baseDate.addingTimeInterval(TimeInterval(index) * 1800),
                actualCompletion: index == 5 ? nil : baseDate.addingTimeInterval(TimeInterval(index) * 1800 + Double(index - 6) * 60),
                deltaMinutes: index == 5 ? 0 : index - 6
            )
        }
        let report = makeReport(entries: entries, shifts: 5)

        let data = generator.generate(report: report, event: event)
        let document = PDFDocument(data: data)

        #expect(document != nil)
        #expect((document?.pageCount ?? 0) >= 1)
    }
}
#endif
