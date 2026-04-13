import SwiftUI
import Models
import Services

/// Grid view showing all available event templates as tappable cards.
struct TemplateBrowserView: View {

    @State private var templates: [Template] = []
    @State private var loadError: String?

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
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(String(localized: "Templates"))
        .navigationBarTitleDisplayMode(.large)
        .task {
            loadTemplates()
        }
    }

    private func loadTemplates() {
        do {
            let loader = TemplateLoader()
            let directory = URL(fileURLWithPath: Bundle.main.bundlePath)
                .appendingPathComponent("Templates")
            if FileManager.default.fileExists(atPath: directory.path) {
                templates = try loader.loadAll(from: directory)
                    .sorted { $0.name < $1.name }
            } else {
                templates = try loader.loadAll(from: .main)
                    .sorted { $0.name < $1.name }
            }
        } catch {
            loadError = error.localizedDescription
        }
    }
}

// MARK: - Template Card

private struct TemplateCardView: View {

    let template: Template

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            timelineThumbnail
                .frame(height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Text(template.name)
                .font(.headline)
                .lineLimit(1)

            Text(template.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack {
                Label("\(template.blocks.count)", systemImage: "rectangle.stack")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(template.category.displayName)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(template.category.tintColor.opacity(0.15))
                    .foregroundStyle(template.category.tintColor)
                    .clipShape(Capsule())
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 3, y: 2)
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

    var tintColor: Color {
        switch self {
        case .wedding: .pink
        case .corporate: .blue
        case .social: .orange
        case .photography: .purple
        }
    }
}
