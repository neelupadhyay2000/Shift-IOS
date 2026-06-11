import Models
import SwiftUI

/// Coming-soon teaser for the Community segment of the Templates tab.
///
/// Templates become a shared space: pros publish their run-sheets and browse
/// templates from other planners and photographers. Until that ships, this
/// teaser sets the expectation and nudges users to build their own library
/// now ("Save as Template" on any event) so they have something to publish
/// on day one.
///
/// Designed as plain content (no ScrollView) so `TemplateBrowserView` can
/// embed it under the section picker inside its own scroll view.
struct CommunityTemplatesTeaserView: View {

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            heroSection
            previewSection
            buildYourLibraryCard
        }
        .padding(20)
        // Readable column on iPad / wide layouts; full width on iPhone.
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier(AccessibilityID.Templates.communityTeaser)
        .onAppear {
            // Once per app session, however often the segment is revisited —
            // measures unique teaser reach, not segment switches.
            guard !CommunityTeaserSignalGuard.hasFiredThisSession else { return }
            CommunityTeaserSignalGuard.hasFiredThisSession = true
            AnalyticsService.send(.communityTemplatesTeaserViewed)
        }
    }

    // MARK: Hero

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Coming Soon")).microLabel()
            Text(String(localized: "Run-sheets from pros who've actually run them."))
                .font(.title.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            Text(String(localized: """
            Community templates let you browse and apply timelines shared by \
            working planners and photographers — and publish your own. Every \
            shared template starts as a real event run in Shift.
            """))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Preview cards

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "What's coming")).microLabel()
            VStack(spacing: 12) {
                ForEach(CommunityTemplatePreview.samples) { preview in
                    CommunityTemplatePreviewCard(preview: preview)
                }
            }
            Text(String(localized: "Example templates. Real community templates arrive when sharing opens."))
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Build-your-library nudge

    private var buildYourLibraryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(String(localized: "Start your library now"))
                    .font(.headline)
            } icon: {
                Image(systemName: "rectangle.stack.badge.plus")
                    .foregroundStyle(ShiftPalette.accent)
            }
            Text(String(localized: """
            Open any event and tap "Save as Template" to keep its timeline. \
            Your saved templates live in the Library — and they'll be ready \
            to share when the community opens.
            """))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .proCard()
    }
}

/// Process-lifetime guard so `templates.communityTeaserViewed` fires once per
/// app session. iPad recreates the detail stack on every tab switch, so view
/// state alone can't provide "once per session".
private enum CommunityTeaserSignalGuard {
    static var hasFiredThisSession = false
}

// MARK: - CommunityTemplatePreviewCard

/// One mocked community template: mini timeline, name, category chip, and the
/// runs-via-Shift badge that will differentiate community templates from
/// self-authored uploads.
private struct CommunityTemplatePreviewCard: View {

    let preview: CommunityTemplatePreview

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(preview.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(preview.category.displayName).microLabel()
            }

            timelineThumbnail
                .frame(height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 8) {
                Label {
                    Text(String(localized: "\(preview.blockCount) blocks"))
                        .font(.caption)
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "rectangle.stack")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)

                Label {
                    Text(String(localized: "Run \(preview.timesRun) times via Shift"))
                        .font(.caption)
                } icon: {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption)
                }
                .foregroundStyle(ShiftPalette.accent)
            }
        }
        .proCard(padding: 14)
        .accessibilityElement(children: .combine)
    }

    /// Mini timeline bars in the same visual language as the library cards.
    private var timelineThumbnail: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.tertiarySystemFill))
                ForEach(Array(preview.bars.enumerated()), id: \.offset) { _, bar in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: bar.colorTag))
                        .frame(width: max(2, geometry.size.width * bar.width), height: 24)
                        .offset(x: geometry.size.width * bar.offset)
                }
            }
        }
    }
}

// MARK: - Mocked preview data

/// Hard-coded example templates for the teaser cards. Purely illustrative;
/// replaced by real community templates when sharing opens.
private struct CommunityTemplatePreview: Identifiable {
    struct Bar {
        let offset: Double
        let width: Double
        let colorTag: String
    }

    let id: String
    let name: String
    let category: TemplateCategory
    let blockCount: Int
    let timesRun: Int
    let bars: [Bar]

    static let samples: [CommunityTemplatePreview] = [
        CommunityTemplatePreview(
            id: "coastal-elopement", name: "Coastal Elopement",
            category: .wedding, blockCount: 11, timesRun: 23,
            bars: [
                Bar(offset: 0.00, width: 0.18, colorTag: "#AF52DE"),
                Bar(offset: 0.20, width: 0.25, colorTag: "#FF3B30"),
                Bar(offset: 0.47, width: 0.20, colorTag: "#FF9500"),
                Bar(offset: 0.69, width: 0.28, colorTag: "#007AFF"),
            ]
        ),
        CommunityTemplatePreview(
            id: "product-launch", name: "Product Launch Night",
            category: .corporate, blockCount: 9, timesRun: 14,
            bars: [
                Bar(offset: 0.00, width: 0.30, colorTag: "#34C759"),
                Bar(offset: 0.32, width: 0.22, colorTag: "#007AFF"),
                Bar(offset: 0.56, width: 0.40, colorTag: "#5856D6"),
            ]
        ),
        CommunityTemplatePreview(
            id: "golden-hour-session", name: "Golden Hour Session",
            category: .photography, blockCount: 6, timesRun: 31,
            bars: [
                Bar(offset: 0.00, width: 0.35, colorTag: "#FF9500"),
                Bar(offset: 0.38, width: 0.30, colorTag: "#FFCC00"),
                Bar(offset: 0.70, width: 0.27, colorTag: "#FF3B30"),
            ]
        ),
    ]
}

// MARK: - Previews

#Preview("Community teaser — light") {
    NavigationStack {
        ScrollView {
            CommunityTemplatesTeaserView()
        }
        .background { ProBackground() }
    }
}

#Preview("Community teaser — dark") {
    NavigationStack {
        ScrollView {
            CommunityTemplatesTeaserView()
        }
        .background { ProBackground() }
    }
    .preferredColorScheme(.dark)
}
