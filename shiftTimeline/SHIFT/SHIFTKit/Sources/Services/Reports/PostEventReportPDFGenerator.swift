#if os(iOS)
import UIKit
import Models

/// Renders a `PostEventReport` as a shareable, colour-coded PDF.
///
/// The output is a US Letter document with three sections:
///   * **Header** — event title, date, total duration, and a one-line
///     summary ("Total drift: +12 min across 4 shifts").
///   * **Comparison table** — one row per block with columns
///     Block · Planned Start · Actual Completion · Delta. Late deltas
///     render in red, on-time/early deltas render in green, uncompleted
///     blocks render an em-dash in neutral grey.
///   * **Totals row** — total drift minutes and total shift count.
///
/// File naming follows `SHIFT_Report_[EventName]_[Date].pdf`, sanitised to
/// alphanumerics + underscore so the file is safe for AirDrop, Mail, Files,
/// and SMB targets.
public final class PostEventReportPDFGenerator: Sendable {

    // MARK: - Layout

    private enum Layout {
        static let pageWidth: CGFloat = 612   // US Letter (8.5" × 72)
        static let pageHeight: CGFloat = 792  // US Letter (11" × 72)
        static let marginH: CGFloat = 40
        static let marginV: CGFloat = 50
        static let contentWidth: CGFloat = pageWidth - marginH * 2

        // Column proportions — must sum to 1.0.
        static let colTitle: CGFloat = 0.34
        static let colPlanned: CGFloat = 0.22
        static let colActual: CGFloat = 0.22
        static let colDelta: CGFloat = 0.22

        static let rowPadding: CGFloat = 8
        static let headerHeight: CGFloat = 26
        static let totalsRowHeight: CGFloat = 30
    }

    private enum PDFColor {
        static let headerBg = UIColor(red: 0.15, green: 0.15, blue: 0.20, alpha: 1.0)
        static let headerText = UIColor.white
        static let rowAlt = UIColor(red: 0.96, green: 0.96, blue: 0.98, alpha: 1.0)
        static let totalsBg = UIColor(red: 0.92, green: 0.93, blue: 0.96, alpha: 1.0)
        static let bodyText = UIColor.black
        static let lightText = UIColor.gray
        static let subtitle = UIColor.darkGray
        static let tableBorder = UIColor(red: 0.80, green: 0.80, blue: 0.83, alpha: 1.0)

        // Delta tones — green for on-time/early, red for late, grey for n/a.
        static let deltaLate = UIColor(red: 0.80, green: 0.15, blue: 0.20, alpha: 1.0)
        static let deltaOnTime = UIColor(red: 0.15, green: 0.55, blue: 0.30, alpha: 1.0)
        static let deltaNeutral = UIColor.gray
    }

    private enum PDFFont {
        static let title = UIFont.systemFont(ofSize: 22, weight: .bold)
        static let subtitle = UIFont.systemFont(ofSize: 12, weight: .medium)
        static let summary = UIFont.systemFont(ofSize: 12, weight: .semibold)
        static let tableHeader = UIFont.systemFont(ofSize: 9, weight: .bold)
        static let tableBody = UIFont.systemFont(ofSize: 10, weight: .regular)
        static let tableBodyBold = UIFont.systemFont(ofSize: 10, weight: .semibold)
        static let totals = UIFont.systemFont(ofSize: 11, weight: .bold)
        static let footer = UIFont.systemFont(ofSize: 8, weight: .regular)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter
    }()

    private static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // MARK: - Init

    public init() {}

    // MARK: - Public API

    /// Generates the PDF for `report` describing `event`. The two are passed
    /// separately because the report is a value type that may be re-rendered
    /// from a stored snapshot without the live model graph.
    public func generate(report: PostEventReport, event: EventModel) -> Data {
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: Layout.pageWidth, height: Layout.pageHeight)
        )
        let rows = buildRows(report: report)
        let summary = summaryLine(for: report)

        return renderer.pdfData { context in
            var cursor = Cursor()
            beginPage(context: context, cursor: &cursor)

            drawHeader(event: event, summaryLine: summary, cursor: &cursor)

            cursor.y += 12
            drawTableHeader(cursor: &cursor)

            for (index, row) in rows.enumerated() {
                let rowHeight = Layout.rowPadding * 2 + 14

                if cursor.y + rowHeight + Layout.totalsRowHeight > Layout.pageHeight - Layout.marginV {
                    drawFooter(context: context, page: cursor.page)
                    beginPage(context: context, cursor: &cursor)
                    drawTableHeader(cursor: &cursor)
                }

                drawTableRow(row, at: cursor.y, index: index, height: rowHeight)
                cursor.y += rowHeight
            }

            drawTotalsRow(report: report, at: cursor.y)
            cursor.y += Layout.totalsRowHeight

            drawFooter(context: context, page: cursor.page)
        }
    }

    /// `SHIFT_Report_[EventName]_[Date].pdf`. Title is sanitised to
    /// alphanumerics + `_`; characters such as `/`, `:`, `&` are stripped.
    public func fileName(for event: EventModel) -> String {
        let safeTitle = event.title
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
        let safe = safeTitle.isEmpty ? "Event" : safeTitle
        let dateString = Self.fileDateFormatter.string(from: event.date)
        return "SHIFT_Report_\(safe)_\(dateString).pdf"
    }

    /// "Total drift: +12 min across 4 shifts" — used both in the PDF header
    /// and as a preview string for the Share sheet.
    public func summaryLine(for report: PostEventReport) -> String {
        let drift = report.totalDriftMinutes
        let sign = drift > 0 ? "+" : (drift < 0 ? "-" : "")
        let magnitude = abs(drift)
        let shifts = report.totalShiftCount
        let shiftWord = shifts == 1 ? "shift" : "shifts"
        return "Total drift: \(sign)\(magnitude) min across \(shifts) \(shiftWord)"
    }

    // MARK: - Row Model

    /// Tone bucket for a delta cell — drives both colour and the sign prefix.
    public enum DeltaTone: Sendable, Equatable {
        case late      // delta > 0  → red
        case early     // delta < 0  → green
        case onTime    // delta == 0 → green
        case neutral   // never completed → grey
    }

    /// View-model row for a single block in the table. Public so tests can
    /// assert against the rendered data without rasterising the PDF.
    public struct ReportRow: Sendable, Equatable {
        public let title: String
        public let plannedStartDisplay: String
        public let actualCompletionDisplay: String
        public let deltaDisplay: String
        public let deltaMinutes: Int
        public let deltaTone: DeltaTone
    }

    /// Pure transform from `PostEventReport` to renderable rows.
    public func buildRows(report: PostEventReport) -> [ReportRow] {
        report.entries.map { entry in
            let plannedDisplay = Self.timeFormatter.string(from: entry.plannedStart)
            let (actualDisplay, deltaDisplay, tone): (String, String, DeltaTone) = {
                guard let actual = entry.actualCompletion else {
                    return ("—", "—", .neutral)
                }
                let actualString = Self.timeFormatter.string(from: actual)
                let delta = entry.deltaMinutes
                let prefix = delta > 0 ? "+" : (delta < 0 ? "-" : "")
                let display = "\(prefix)\(abs(delta)) min"
                let tone: DeltaTone
                if delta > 0 { tone = .late }
                else if delta < 0 { tone = .early }
                else { tone = .onTime }
                return (actualString, display, tone)
            }()

            return ReportRow(
                title: entry.blockTitle,
                plannedStartDisplay: plannedDisplay,
                actualCompletionDisplay: actualDisplay,
                deltaDisplay: deltaDisplay,
                deltaMinutes: entry.deltaMinutes,
                deltaTone: tone
            )
        }
    }

    // MARK: - Drawing Helpers

    private struct Cursor {
        var y: CGFloat = 0
        var page: Int = 0
    }

    private func beginPage(context: UIGraphicsPDFRendererContext, cursor: inout Cursor) {
        context.beginPage()
        cursor.page += 1
        cursor.y = Layout.marginV
    }

    private func drawHeader(event: EventModel, summaryLine: String, cursor: inout Cursor) {
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: PDFFont.title,
            .foregroundColor: PDFColor.bodyText,
        ]
        (event.title as NSString).draw(
            at: CGPoint(x: Layout.marginH, y: cursor.y),
            withAttributes: titleAttrs
        )
        cursor.y += 28

        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: PDFFont.subtitle,
            .foregroundColor: PDFColor.subtitle,
        ]
        let dateString = Self.dateFormatter.string(from: event.date)
        (("📅  " + dateString) as NSString).draw(
            at: CGPoint(x: Layout.marginH, y: cursor.y),
            withAttributes: subtitleAttrs
        )
        cursor.y += 18

        let label = "Post-Event Report"
        (label as NSString).draw(
            at: CGPoint(x: Layout.marginH, y: cursor.y),
            withAttributes: subtitleAttrs
        )
        cursor.y += 22

        // Summary line in semibold black.
        let summaryAttrs: [NSAttributedString.Key: Any] = [
            .font: PDFFont.summary,
            .foregroundColor: PDFColor.bodyText,
        ]
        (summaryLine as NSString).draw(
            at: CGPoint(x: Layout.marginH, y: cursor.y),
            withAttributes: summaryAttrs
        )
        cursor.y += 18
    }

    private func drawTableHeader(cursor: inout Cursor) {
        let headerRect = CGRect(
            x: Layout.marginH,
            y: cursor.y,
            width: Layout.contentWidth,
            height: Layout.headerHeight
        )
        PDFColor.headerBg.setFill()
        UIBezierPath(
            roundedRect: headerRect,
            byRoundingCorners: [.topLeft, .topRight],
            cornerRadii: CGSize(width: 4, height: 4)
        ).fill()

        let columns: [(String, CGFloat)] = [
            ("BLOCK", Layout.colTitle),
            ("PLANNED START", Layout.colPlanned),
            ("ACTUAL COMPLETION", Layout.colActual),
            ("DELTA", Layout.colDelta),
        ]

        let attrs: [NSAttributedString.Key: Any] = [
            .font: PDFFont.tableHeader,
            .foregroundColor: PDFColor.headerText,
        ]

        var x = Layout.marginH + 8
        for (label, proportion) in columns {
            let colWidth = Layout.contentWidth * proportion
            (label as NSString).draw(
                at: CGPoint(x: x, y: cursor.y + 8),
                withAttributes: attrs
            )
            x += colWidth
        }

        cursor.y += Layout.headerHeight
    }

    private func drawTableRow(_ row: ReportRow, at y: CGFloat, index: Int, height: CGFloat) {
        let rowRect = CGRect(x: Layout.marginH, y: y, width: Layout.contentWidth, height: height)

        if index % 2 == 1 {
            PDFColor.rowAlt.setFill()
            UIBezierPath(rect: rowRect).fill()
        }

        // Bottom border
        let borderPath = UIBezierPath()
        borderPath.move(to: CGPoint(x: Layout.marginH, y: y + height))
        borderPath.addLine(to: CGPoint(x: Layout.marginH + Layout.contentWidth, y: y + height))
        PDFColor.tableBorder.setStroke()
        borderPath.lineWidth = 0.25
        borderPath.stroke()

        let textY = y + Layout.rowPadding
        var x = Layout.marginH + 8

        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: PDFFont.tableBody,
            .foregroundColor: PDFColor.bodyText,
        ]
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: PDFFont.tableBodyBold,
            .foregroundColor: PDFColor.bodyText,
        ]

        // Title (truncated by clipping the rect).
        let titleWidth = Layout.contentWidth * Layout.colTitle - 8
        (row.title as NSString).draw(
            in: CGRect(x: x, y: textY, width: titleWidth, height: height),
            withAttributes: titleAttrs
        )
        x += Layout.contentWidth * Layout.colTitle

        // Planned start.
        let plannedWidth = Layout.contentWidth * Layout.colPlanned - 8
        (row.plannedStartDisplay as NSString).draw(
            in: CGRect(x: x, y: textY, width: plannedWidth, height: height),
            withAttributes: bodyAttrs
        )
        x += Layout.contentWidth * Layout.colPlanned

        // Actual completion.
        let actualWidth = Layout.contentWidth * Layout.colActual - 8
        (row.actualCompletionDisplay as NSString).draw(
            in: CGRect(x: x, y: textY, width: actualWidth, height: height),
            withAttributes: bodyAttrs
        )
        x += Layout.contentWidth * Layout.colActual

        // Delta — colour-coded.
        let deltaColor: UIColor
        switch row.deltaTone {
        case .late: deltaColor = PDFColor.deltaLate
        case .early, .onTime: deltaColor = PDFColor.deltaOnTime
        case .neutral: deltaColor = PDFColor.deltaNeutral
        }
        let deltaAttrs: [NSAttributedString.Key: Any] = [
            .font: PDFFont.tableBodyBold,
            .foregroundColor: deltaColor,
        ]
        let deltaWidth = Layout.contentWidth * Layout.colDelta - 8
        (row.deltaDisplay as NSString).draw(
            in: CGRect(x: x, y: textY, width: deltaWidth, height: height),
            withAttributes: deltaAttrs
        )
    }

    private func drawTotalsRow(report: PostEventReport, at y: CGFloat) {
        let rowRect = CGRect(
            x: Layout.marginH,
            y: y,
            width: Layout.contentWidth,
            height: Layout.totalsRowHeight
        )
        PDFColor.totalsBg.setFill()
        UIBezierPath(rect: rowRect).fill()

        let topBorder = UIBezierPath()
        topBorder.move(to: CGPoint(x: Layout.marginH, y: y))
        topBorder.addLine(to: CGPoint(x: Layout.marginH + Layout.contentWidth, y: y))
        PDFColor.headerBg.setStroke()
        topBorder.lineWidth = 1.0
        topBorder.stroke()

        let textY = y + (Layout.totalsRowHeight - 14) / 2

        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: PDFFont.totals,
            .foregroundColor: PDFColor.bodyText,
        ]
        ("TOTAL" as NSString).draw(
            at: CGPoint(x: Layout.marginH + 8, y: textY),
            withAttributes: labelAttrs
        )

        // Shift count under the "ACTUAL COMPLETION" column.
        let shiftCountX = Layout.marginH + Layout.contentWidth * (Layout.colTitle + Layout.colPlanned) + 8
        let shiftLabel = "\(report.totalShiftCount) shift\(report.totalShiftCount == 1 ? "" : "s")"
        (shiftLabel as NSString).draw(
            at: CGPoint(x: shiftCountX, y: textY),
            withAttributes: labelAttrs
        )

        // Total drift under the "DELTA" column, colour-coded.
        let driftX = Layout.marginH + Layout.contentWidth * (Layout.colTitle + Layout.colPlanned + Layout.colActual) + 8
        let drift = report.totalDriftMinutes
        let prefix = drift > 0 ? "+" : (drift < 0 ? "-" : "")
        let driftText = "\(prefix)\(abs(drift)) min"
        let driftColor: UIColor = drift > 0 ? PDFColor.deltaLate : PDFColor.deltaOnTime
        let driftAttrs: [NSAttributedString.Key: Any] = [
            .font: PDFFont.totals,
            .foregroundColor: driftColor,
        ]
        (driftText as NSString).draw(
            at: CGPoint(x: driftX, y: textY),
            withAttributes: driftAttrs
        )
    }

    private func drawFooter(context: UIGraphicsPDFRendererContext, page: Int) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: PDFFont.footer,
            .foregroundColor: PDFColor.lightText,
        ]
        let text = "Generated by SHIFT — Page \(page)"
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(
            at: CGPoint(
                x: Layout.pageWidth - Layout.marginH - size.width,
                y: Layout.pageHeight - Layout.marginV + 20
            ),
            withAttributes: attrs
        )
    }
}
#endif
