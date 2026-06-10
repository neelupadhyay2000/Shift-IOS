import SwiftUI
import Models
import Services

/// Grid view showing all available event templates as tappable cards.
struct TemplateBrowserView: View {

    @State private var templates: [Template] = []
    @State private var loadError: String?
    @State private var isLoading = true

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    var body: some View {
        ScrollView {
            if let loadError {
                ContentUnavailableView(
                    String(localized: "Unable to Load Templates"),
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else if templates.isEmpty {
                ContentUnavailableView(
                    String(localized: "No Templates"),
                    systemImage: "square.grid.2x2",
                    description: Text(String(localized: "Templates will appear here."))
                )
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(templates) { template in
                        NavigationLink(value: TemplateDestination.templatePreview(templateID: template.id)) {
                            TemplateCardView(template: template)
                        }
                        .buttonStyle(.pressableCard)
                    }
                }
                .padding()
            }
        }
        .background { ProBackground() }
        .accessibilityIdentifier(AccessibilityID.Templates.templateList)
        .navigationTitle(String(localized: "Templates"))
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadTemplates()
        }
    }

    private func loadTemplates() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let loaded = try await Task(priority: .userInitiated) {
                try TemplateLoader().loadAll().sorted { $0.name < $1.name }
            }.value
            guard !Task.isCancelled else { return }
            templates = loaded
        } catch {
            guard !Task.isCancelled else { return }
            loadError = error.localizedDescription
        }
    }
}

// MARK: - Template Card

private struct TemplateCardView: View {

    let template: Template

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The mini-timeline carries the personality; the chrome stays quiet.
            Text(template.category.displayName).microLabel()

            timelineThumbnail
                .frame(height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(template.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)

            Text(template.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 4) {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 10, weight: .medium))
                Text("\(template.blocks.count)")
                    .monospacedDigit()
                Text(String(localized: "blocks"))
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .proCard(padding: 12)
    }

    /// Mini timeline thumbnail showing colored bars for each block.
    private var timelineThumbnail: some View {
        GeometryReader { geometry in
            let totalDuration = templateTotalDuration
            if totalDuration > 0 {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.tertiarySystemFill))

                    ForEach(Array(template.blocks.enumerated()), id: \.offset) { _, block in
                        let xOffset = geometry.size.width * (block.relativeStartOffset / totalDuration)
                        let width = max(2, geometry.size.width * (block.duration / totalDuration))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: block.colorTag))
                            .frame(width: width, height: block.isPinned ? 40 : 28)
                            .offset(x: xOffset)
                    }
                }
            }
        }
    }

    private var templateTotalDuration: TimeInterval {
        template.blocks.map { $0.relativeStartOffset + $0.duration }.max() ?? 1
    }
}

// MARK: - TemplateCategory Display Helpers

extension TemplateCategory {
    var displayName: String {
        switch self {
        case .wedding: String(localized: "Wedding")
        case .corporate: String(localized: "Corporate")
        case .social: String(localized: "Social")
        case .photography: String(localized: "Photography")
        }
    }
}
