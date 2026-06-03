import SwiftUI

// MARK: - Document Model

/// A structured legal document (Privacy Policy / Terms of Service) rendered
/// natively instead of via an embedded web page. Content is plain text with
/// lightweight inline markdown (`**bold**`) supported inside paragraphs and
/// list items.
struct LegalDocument {
    let title: String
    /// Preamble / recital shown beneath the title rule.
    let summary: String
    let lastUpdated: Date
    let sections: [LegalSection]
}

struct LegalSection: Identifiable {
    let id = UUID()
    let heading: String
    let blocks: [LegalBlock]
}

/// A single renderable unit within a section.
enum LegalBlock {
    case paragraph(String)
    case subheading(String)
    case bullets([String])
}

// MARK: - Renderer

/// Native renderer for a `LegalDocument`, styled to read like a formal legal
/// instrument: a serif face, a titled header rule, an outline layout with large
/// section numerals in a left gutter, ALL-CAPS headings, small dense body text,
/// and lettered sub-clauses. Monochrome by design — no accent color or imagery.
/// All type uses semantic styles so it scales with Dynamic Type.
struct LegalDocumentView: View {

    let document: LegalDocument

    private let bodyFont: Font = .system(.footnote, design: .serif)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                ForEach(Array(document.sections.enumerated()), id: \.offset) { index, section in
                    sectionView(number: index + 1, section: section)
                }
                footer
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
        .background(Color(.systemBackground))
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(document.title)
                    .font(.system(.largeTitle, design: .serif).weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(effectiveDateLabel)
                    .font(.system(.caption, design: .serif).weight(.semibold))
                    .tracking(1.0)
                    .foregroundStyle(.secondary)
            }

            Rectangle()
                .fill(.primary.opacity(0.25))
                .frame(height: 1)

            Text(attributed(document.summary))
                .font(bodyFont)
                .lineSpacing(4)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Rectangle()
                .fill(.primary.opacity(0.12))
                .frame(height: 1)
        }
    }

    private var effectiveDateLabel: String {
        let date = document.lastUpdated.formatted(.dateTime.month(.wide).day().year())
        return String(localized: "Effective Date: \(date)").uppercased()
    }

    // MARK: Section

    private func sectionView(number: Int, section: LegalSection) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("\(number)")
                .font(.system(.title, design: .serif))
                .foregroundStyle(.primary)
                .frame(width: 30, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                Text(section.heading.uppercased())
                    .font(.system(.subheadline, design: .serif).weight(.bold))
                    .tracking(0.5)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(Array(section.blocks.enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
            }
        }
    }

    // MARK: Block

    @ViewBuilder
    private func blockView(_ block: LegalBlock) -> some View {
        switch block {
        case .paragraph(let text):
            Text(attributed(text))
                .font(bodyFont)
                .lineSpacing(4)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

        case .subheading(let text):
            Text(text.uppercased())
                .font(bodyFont.weight(.bold))
                .tracking(0.5)
                .padding(.top, 2)
                .fixedSize(horizontal: false, vertical: true)

        case .bullets(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(clauseMarker(index))
                            .font(bodyFont)
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .leading)
                        Text(attributed(item))
                            .font(bodyFont)
                            .lineSpacing(4)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle()
                .fill(.primary.opacity(0.12))
                .frame(height: 1)
            Text(verbatim: "\(LegalContent.appName) · \(LegalContent.companyName)")
                .font(.system(.caption2, design: .serif))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    // MARK: Helpers

    /// Lettered sub-clause marker: "(a)", "(b)", … falling back to a number
    /// beyond the alphabet so long lists never break.
    private func clauseMarker(_ index: Int) -> String {
        guard index < 26, let scalar = UnicodeScalar(97 + index) else {
            return "(\(index + 1))"
        }
        return "(\(Character(scalar)))"
    }

    /// Renders lightweight inline markdown (e.g. `**bold**`) while preserving
    /// the original whitespace. Falls back to the raw string if parsing fails.
    private func attributed(_ string: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: string, options: options))
            ?? AttributedString(string)
    }
}

// MARK: - Preview

#Preview("Privacy Policy") {
    NavigationStack {
        LegalDocumentView(document: LegalContent.privacyPolicy)
    }
}

#Preview("Terms of Service") {
    NavigationStack {
        LegalDocumentView(document: LegalContent.termsOfService)
    }
}
