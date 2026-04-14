#if os(iOS)
import UIKit
import Models

/// Generates a professional PDF document from an event's timeline data.
///
/// Usage:
/// ```swift
/// let generator = PDFGenerator()
/// let data = generator.generate(from: event)
/// ```
///
/// The output includes:
/// - Event title, date, and venue
/// - A formatted table of all blocks (time, title, duration, vendor, notes)
/// - Sunset and golden hour rows visually highlighted
public final class PDFGenerator: Sendable {

    // MARK: - Layout Constants

    private enum Layout {
        static let pageWidth: CGFloat = 612   // US Letter
        static let pageHeight: CGFloat = 792
        static let marginH: CGFloat = 40
        static let marginV: CGFloat = 50
        static let contentWidth: CGFloat = pageWidth - marginH * 2

        // Table column proportions (must sum to 1.0)
        static let colTime: CGFloat = 0.13
        static let colTitle: CGFloat = 0.22
        static let colDuration: CGFloat = 0.10
        static let colVendor: CGFloat = 0.22
        static let colNotes: CGFloat = 0.33

        static let rowPadding: CGFloat = 6
        static let headerHeight: CGFloat = 24
    }

    // MARK: - Colors

    private enum PDFColor {
        static let headerBg = UIColor(red: 0.15, green: 0.15, blue: 0.20, alpha: 1.0)
        static let headerText = UIColor.white
        static let rowAlt = UIColor(red: 0.96, green: 0.96, blue: 0.98, alpha: 1.0)
        static let sunsetBg = UIColor(red: 1.0, green: 0.85, blue: 0.60, alpha: 0.30)
        static let sunsetBorder = UIColor(red: 0.95, green: 0.60, blue: 0.10, alpha: 1.0)
        static let goldenBg = UIColor(red: 1.0, green: 0.93, blue: 0.55, alpha: 0.25)
        static let goldenBorder = UIColor(red: 0.85, green: 0.75, blue: 0.10, alpha: 1.0)
        static let accent = UIColor(red: 0.20, green: 0.40, blue: 0.90, alpha: 1.0)
        static let subtitleText = UIColor.darkGray
        static let bodyText = UIColor.black
        static let lightText = UIColor.gray
        static let tableBorder = UIColor(red: 0.80, green: 0.80, blue: 0.83, alpha: 1.0)
    }

    // MARK: - Fonts

    private enum PDFFont {
        static let title = UIFont.systemFont(ofSize: 22, weight: .bold)
        static let subtitle = UIFont.systemFont(ofSize: 12, weight: .medium)
        static let sectionHeader = UIFont.systemFont(ofSize: 14, weight: .bold)
        static let tableHeader = UIFont.systemFont(ofSize: 9, weight: .bold)
        static let tableBody = UIFont.systemFont(ofSize: 9, weight: .regular)
        static let tableBodyBold = UIFont.systemFont(ofSize: 9, weight: .semibold)
        static let footer = UIFont.systemFont(ofSize: 8, weight: .regular)
        static let highlight = UIFont.systemFont(ofSize: 9, weight: .semibold)
    }

    // MARK: - Formatters

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        return f
    }()

    // MARK: - Init

    public init() {}

    // MARK: - Public API

    /// Generates a PDF `Data` blob for the given event.
    ///
    /// Blocks are sorted chronologically across all tracks.
    /// Sunset and golden hour times are inserted as highlighted rows.
    public func generate(from event: EventModel) -> Data {
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: Layout.pageWidth, height: Layout.pageHeight)
        )

        let allBlocks = event.tracks
            .flatMap(\.blocks)
            .sorted { $0.scheduledStart < $1.scheduledStart }

        // Build row data
        var rows = allBlocks.map { block in
            TableRow(
                time: Self.timeFormatter.string(from: block.scheduledStart),
                title: block.title,
                duration: Self.formatDuration(block.duration),
                vendor: block.vendors.map(\.name).joined(separator: ", "),
                notes: block.notes,
                highlight: .none,
                isPinned: block.isPinned
            )
        }

        // Insert sunset/golden hour marker rows
        if let sunset = event.sunsetTime {
            let sunsetRow = TableRow(
                time: Self.timeFormatter.string(from: sunset),
                title: "☀ Sunset",
                duration: "",
                vendor: "",
                notes: "Sunset — plan outdoor activities before this time",
                highlight: .sunset,
                isPinned: false
            )
            insertChronologically(&rows, row: sunsetRow, date: sunset, allBlocks: allBlocks)
        }
        if let golden = event.goldenHourStart {
            let goldenRow = TableRow(
                time: Self.timeFormatter.string(from: golden),
                title: "✦ Golden Hour",
                duration: "",
                vendor: "",
                notes: "Best natural lighting for photos",
                highlight: .goldenHour,
                isPinned: false
            )
            insertChronologically(&rows, row: goldenRow, date: golden, allBlocks: allBlocks)
        }

        return renderer.pdfData { context in
            var cursor = Cursor()
            beginPage(context: context, cursor: &cursor)

            // Header
            drawHeader(event: event, cursor: &cursor)

            // Venue
            if !event.venueNames.isEmpty {
                let venue = event.venueNames.joined(separator: ", ")
                drawSubtitleLine(icon: "📍", text: venue, cursor: &cursor)
            }

            // Track summary
            let trackSummary = event.tracks
                .sorted { $0.sortOrder < $1.sortOrder }
                .map { "\($0.name) (\($0.blocks.count))" }
                .joined(separator: " · ")
            if !trackSummary.isEmpty {
                drawSubtitleLine(icon: "🎵", text: "Tracks: \(trackSummary)", cursor: &cursor)
            }

            cursor.y += 16

            // Table
            drawTableHeader(cursor: &cursor)

            for (index, row) in rows.enumerated() {
                let rowHeight = calculateRowHeight(row)
                let totalRowHeight = rowHeight + Layout.rowPadding * 2

                // Page break check
                if cursor.y + totalRowHeight > Layout.pageHeight - Layout.marginV - 20 {
                    drawFooter(context: context, page: cursor.page)
                    beginPage(context: context, cursor: &cursor)
                    drawTableHeader(cursor: &cursor)
                }

                drawTableRow(row, at: cursor.y, index: index)
                cursor.y += totalRowHeight
            }

            // Bottom border
            let borderPath = UIBezierPath()
            borderPath.move(to: CGPoint(x: Layout.marginH, y: cursor.y))
            borderPath.addLine(to: CGPoint(x: Layout.marginH + Layout.contentWidth, y: cursor.y))
            PDFColor.tableBorder.setStroke()
            borderPath.lineWidth = 0.5
            borderPath.stroke()

            cursor.y += 20

            // Summary line
            let summaryText = "\(allBlocks.count) blocks across \(event.tracks.count) track(s)"
            let summaryAttrs: [NSAttributedString.Key: Any] = [
                .font: PDFFont.subtitle,
                .foregroundColor: PDFColor.lightText,
            ]
            (summaryText as NSString).draw(
                at: CGPoint(x: Layout.marginH, y: cursor.y),
                withAttributes: summaryAttrs
            )

            drawFooter(context: context, page: cursor.page)
        }
    }

    // MARK: - Data Types

    private struct TableRow {
        let time: String
        let title: String
        let duration: String
        let vendor: String
        let notes: String
        let highlight: HighlightKind
        let isPinned: Bool
    }

    private enum HighlightKind {
        case none
        case sunset
        case goldenHour
    }

    private struct Cursor {
        var y: CGFloat = 0
        var page: Int = 0
    }

    // MARK: - Page Management

    private func beginPage(context: UIGraphicsPDFRendererContext, cursor: inout Cursor) {
        context.beginPage()
        cursor.page += 1
        cursor.y = Layout.marginV
    }

    // MARK: - Header Drawing

    private func drawHeader(event: EventModel, cursor: inout Cursor) {
        // Title
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: PDFFont.title,
            .foregroundColor: PDFColor.bodyText,
        ]
        let titleSize = (event.title as NSString).boundingRect(
            with: CGSize(width: Layout.contentWidth, height: .greatestFiniteMagnitude),
            options: .usesLineFragmentOrigin,
            attributes: titleAttrs,
            context: nil
        )
        (event.title as NSString).draw(
            in: CGRect(x: Layout.marginH, y: cursor.y, width: Layout.contentWidth, height: titleSize.height),
            withAttributes: titleAttrs
        )
        cursor.y += titleSize.height + 4

        // Date line
        let dateStr = Self.dateFormatter.string(from: event.date)
        drawSubtitleLine(icon: "📅", text: dateStr, cursor: &cursor)

        // Status badge
        let statusText = event.status.rawValue.capitalized
        let statusAttrs: [NSAttributedString.Key: Any] = [
            .font: PDFFont.subtitle,
            .foregroundColor: PDFColor.accent,
        ]
        let statusSize = (statusText as NSString).size(withAttributes: statusAttrs)
        let badgeRect = CGRect(
            x: Layout.marginH + Layout.contentWidth - statusSize.width - 12,
            y: cursor.y - statusSize.height - 6,
            width: statusSize.width + 12,
            height: statusSize.height + 6
        )
        let badgePath = UIBezierPath(roundedRect: badgeRect, cornerRadius: 4)
        PDFColor.accent.withAlphaComponent(0.1).setFill()
        badgePath.fill()
        PDFColor.accent.setStroke()
        badgePath.lineWidth = 0.5
        badgePath.stroke()
        (statusText as NSString).draw(
            at: CGPoint(x: badgeRect.minX + 6, y: badgeRect.minY + 3),
            withAttributes: statusAttrs
        )
    }

    private func drawSubtitleLine(icon: String, text: String, cursor: inout Cursor) {
        let lineText = "\(icon)  \(text)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: PDFFont.subtitle,
            .foregroundColor: PDFColor.subtitleText,
        ]
        let size = (lineText as NSString).boundingRect(
            with: CGSize(width: Layout.contentWidth, height: .greatestFiniteMagnitude),
            options: .usesLineFragmentOrigin,
            attributes: attrs,
            context: nil
        )
        (lineText as NSString).draw(
            in: CGRect(x: Layout.marginH, y: cursor.y, width: Layout.contentWidth, height: size.height),
            withAttributes: attrs
        )
        cursor.y += size.height + 4
    }

    // MARK: - Table Drawing

    private func drawTableHeader(cursor: inout Cursor) {
        let headerRect = CGRect(
            x: Layout.marginH,
            y: cursor.y,
            width: Layout.contentWidth,
            height: Layout.headerHeight
        )
        UIBezierPath(roundedRect: headerRect, byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: 4, height: 4)).fill(with: PDFColor.headerBg)

        let columns: [(String, CGFloat)] = [
            ("TIME", Layout.colTime),
            ("BLOCK", Layout.colTitle),
            ("DURATION", Layout.colDuration),
            ("VENDOR", Layout.colVendor),
            ("NOTES", Layout.colNotes),
        ]

        let attrs: [NSAttributedString.Key: Any] = [
            .font: PDFFont.tableHeader,
            .foregroundColor: PDFColor.headerText,
        ]

        var x = Layout.marginH + 6
        for (label, proportion) in columns {
            let colWidth = Layout.contentWidth * proportion
            (label as NSString).draw(
                at: CGPoint(x: x, y: cursor.y + 7),
                withAttributes: attrs
            )
            x += colWidth
        }

        cursor.y += Layout.headerHeight
    }

    private func drawTableRow(_ row: TableRow, at y: CGFloat, index: Int) {
        let rowHeight = calculateRowHeight(row)
        let totalRowHeight = rowHeight + Layout.rowPadding * 2
        let rowRect = CGRect(
            x: Layout.marginH,
            y: y,
            width: Layout.contentWidth,
            height: totalRowHeight
        )

        // Background fill
        switch row.highlight {
        case .sunset:
            PDFColor.sunsetBg.setFill()
            UIBezierPath(rect: rowRect).fill()
            // Left accent bar
            let accentRect = CGRect(x: Layout.marginH, y: y, width: 3, height: totalRowHeight)
            PDFColor.sunsetBorder.setFill()
            UIBezierPath(rect: accentRect).fill()
        case .goldenHour:
            PDFColor.goldenBg.setFill()
            UIBezierPath(rect: rowRect).fill()
            let accentRect = CGRect(x: Layout.marginH, y: y, width: 3, height: totalRowHeight)
            PDFColor.goldenBorder.setFill()
            UIBezierPath(rect: accentRect).fill()
        case .none:
            if index % 2 == 1 {
                PDFColor.rowAlt.setFill()
                UIBezierPath(rect: rowRect).fill()
            }
        }

        // Bottom border
        let borderPath = UIBezierPath()
        borderPath.move(to: CGPoint(x: Layout.marginH, y: y + totalRowHeight))
        borderPath.addLine(to: CGPoint(x: Layout.marginH + Layout.contentWidth, y: y + totalRowHeight))
        PDFColor.tableBorder.setStroke()
        borderPath.lineWidth = 0.25
        borderPath.stroke()

        // Cell content
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: PDFFont.tableBody,
            .foregroundColor: PDFColor.bodyText,
        ]
        let boldAttrs: [NSAttributedString.Key: Any] = [
            .font: PDFFont.tableBodyBold,
            .foregroundColor: PDFColor.bodyText,
        ]
        let highlightAttrs: [NSAttributedString.Key: Any] = [
            .font: PDFFont.highlight,
            .foregroundColor: row.highlight == .sunset ? PDFColor.sunsetBorder : PDFColor.goldenBorder,
        ]

        let textY = y + Layout.rowPadding
        var x = Layout.marginH + 6

        // Time
        let timeWidth = Layout.contentWidth * Layout.colTime
        (row.time as NSString).draw(
            in: CGRect(x: x, y: textY, width: timeWidth - 4, height: rowHeight),
            withAttributes: bodyAttrs
        )
        x += timeWidth

        // Title
        let titleWidth = Layout.contentWidth * Layout.colTitle
        let titleAttrs = row.highlight != .none ? highlightAttrs : boldAttrs
        var titleText = row.title
        if row.isPinned { titleText = "📌 \(titleText)" }
        (titleText as NSString).draw(
            in: CGRect(x: x, y: textY, width: titleWidth - 4, height: rowHeight),
            withAttributes: titleAttrs
        )
        x += titleWidth

        // Duration
        let durationWidth = Layout.contentWidth * Layout.colDuration
        (row.duration as NSString).draw(
            in: CGRect(x: x, y: textY, width: durationWidth - 4, height: rowHeight),
            withAttributes: bodyAttrs
        )
        x += durationWidth

        // Vendor
        let vendorWidth = Layout.contentWidth * Layout.colVendor
        (row.vendor as NSString).draw(
            in: CGRect(x: x, y: textY, width: vendorWidth - 4, height: rowHeight),
            withAttributes: bodyAttrs
        )
        x += vendorWidth

        // Notes
        let notesWidth = Layout.contentWidth * Layout.colNotes
        (row.notes as NSString).draw(
            in: CGRect(x: x, y: textY, width: notesWidth - 10, height: rowHeight),
            withAttributes: bodyAttrs
        )
    }

    private func calculateRowHeight(_ row: TableRow) -> CGFloat {
        let maxNoteWidth = Layout.contentWidth * Layout.colNotes - 10
        let attrs: [NSAttributedString.Key: Any] = [.font: PDFFont.tableBody]
        let notesHeight = (row.notes as NSString).boundingRect(
            with: CGSize(width: maxNoteWidth, height: .greatestFiniteMagnitude),
            options: .usesLineFragmentOrigin,
            attributes: attrs,
            context: nil
        ).height

        let maxVendorWidth = Layout.contentWidth * Layout.colVendor - 4
        let vendorHeight = (row.vendor as NSString).boundingRect(
            with: CGSize(width: maxVendorWidth, height: .greatestFiniteMagnitude),
            options: .usesLineFragmentOrigin,
            attributes: attrs,
            context: nil
        ).height

        return max(14, max(notesHeight, vendorHeight))
    }

    // MARK: - Footer

    private func drawFooter(context: UIGraphicsPDFRendererContext, page: Int) {
        let footerY = Layout.pageHeight - Layout.marginV + 10
        let attrs: [NSAttributedString.Key: Any] = [
            .font: PDFFont.footer,
            .foregroundColor: PDFColor.lightText,
        ]

        // Left: app branding
        let branding = "Generated by SHIFT"
        (branding as NSString).draw(
            at: CGPoint(x: Layout.marginH, y: footerY),
            withAttributes: attrs
        )

        // Right: page number
        let pageText = "Page \(page)"
        let pageSize = (pageText as NSString).size(withAttributes: attrs)
        (pageText as NSString).draw(
            at: CGPoint(x: Layout.marginH + Layout.contentWidth - pageSize.width, y: footerY),
            withAttributes: attrs
        )

        // Separator line
        let linePath = UIBezierPath()
        linePath.move(to: CGPoint(x: Layout.marginH, y: footerY - 4))
        linePath.addLine(to: CGPoint(x: Layout.marginH + Layout.contentWidth, y: footerY - 4))
        PDFColor.tableBorder.setStroke()
        linePath.lineWidth = 0.5
        linePath.stroke()
    }

    // MARK: - Helpers

    private func insertChronologically(
        _ rows: inout [TableRow],
        row: TableRow,
        date: Date,
        allBlocks: [TimeBlockModel]
    ) {
        let insertIndex = allBlocks.firstIndex { $0.scheduledStart > date } ?? allBlocks.count
        // Adjust for previously inserted highlight rows
        let currentCount = rows.count
        let blockCount = allBlocks.count
        let offset = currentCount - blockCount
        rows.insert(row, at: min(insertIndex + offset, rows.count))
    }

    private static func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        if minutes >= 60 {
            let h = minutes / 60
            let m = minutes % 60
            return m > 0 ? "\(h)h \(m)m" : "\(h)h"
        }
        return "\(minutes)m"
    }
}

// MARK: - UIBezierPath fill helper

private extension UIBezierPath {
    func fill(with color: UIColor) {
        color.setFill()
        fill()
    }
}
#endif
