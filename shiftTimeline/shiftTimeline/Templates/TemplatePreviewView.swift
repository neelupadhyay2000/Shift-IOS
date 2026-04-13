import SwiftUI
import Models
import Services

/// Full preview of a template showing all blocks in a scrollable list.
struct TemplatePreviewView: View {

    let templateID: UUID

    @State private var template: Template?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let template {
                templateContent(template)
            } else if let loadError {
                ContentUnavailableView(
                    String(localized: "Unable to Load Template"),
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else {
                ProgressView()
            }
        }
        .navigationTitle(template?.name ?? String(localized: "Template"))
        .navigationBarTitleDisplayMode(.large)
        .task {
            loadTemplate()
        }
    }

    private func templateContent(_ template: Template) -> some View {
        List {
            Section {
                Text(template.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    Label("\(template.blocks.count) blocks", systemImage: "rectangle.stack")
                    Label(formattedDuration(template), systemImage: "clock")
                    Spacer()
                    Text(template.category.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(template.category.tintColor.opacity(0.15))
                        .foregroundStyle(template.category.tintColor)
                        .clipShape(Capsule())
                }
                .font(.subheadline)
            }

            Section(String(localized: "Blocks")) {
                ForEach(Array(template.blocks.enumerated()), id: \.offset) { _, block in
                    TemplateBlockRow(block: block)
                }
            }
        }
    }

    private func loadTemplate() {
        do {
            let loader = TemplateLoader()
            let directory = URL(fileURLWithPath: Bundle.main.bundlePath)
                .appendingPathComponent("Templates")
            let allTemplates: [Template]
            if FileManager.default.fileExists(atPath: directory.path) {
                allTemplates = try loader.loadAll(from: directory)
            } else {
                allTemplates = try loader.loadAll(from: .main)
            }
            template = allTemplates.first { $0.id == templateID }
            if template == nil {
                loadError = String(localized: "Template not found.")
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func formattedDuration(_ template: Template) -> String {
        let totalSeconds = template.blocks.map { $0.relativeStartOffset + $0.duration }.max() ?? 0
        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        if minutes > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(hours)h"
    }
}

// MARK: - Block Row

private struct TemplateBlockRow: View {

    let block: TemplateBlock

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: block.icon)
                .font(.body)
                .foregroundStyle(Color(hex: block.colorTag))
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(block.title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    Text(formattedOffset)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formattedDuration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if block.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var formattedOffset: String {
        let totalMinutes = Int(block.relativeStartOffset) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return "+\(hours):\(String(format: "%02d", minutes))"
    }

    private var formattedDuration: String {
        let minutes = Int(block.duration) / 60
        if minutes >= 60 {
            let h = minutes / 60
            let m = minutes % 60
            return m > 0 ? "\(h)h \(m)m" : "\(h)h"
        }
        return "\(minutes)m"
    }
}
