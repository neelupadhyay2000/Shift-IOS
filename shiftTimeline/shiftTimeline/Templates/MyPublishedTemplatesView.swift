import Models
import SwiftUI

/// The caller's own published community templates, with unpublish / delete — so an
/// author can always take down content they shared (Apple Guideline 1.2 + good UGC
/// hygiene). Reads `myTemplates()` (author RLS); mutations go through the author
/// UPDATE policy.
struct MyPublishedTemplatesView: View {

    @Environment(\.communityTemplateService) private var service

    @State private var templates: [CommunityTemplateRowDTO] = []
    @State private var phase: Phase = .loading

    private enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            case .failed(let message):
                ContentUnavailableView(
                    String(localized: "Couldn’t Load"),
                    systemImage: "wifi.exclamationmark",
                    description: Text(message)
                )
            case .loaded:
                if templates.isEmpty {
                    ContentUnavailableView(
                        String(localized: "Nothing Published Yet"),
                        systemImage: "square.and.arrow.up",
                        description: Text(String(localized: "Publish a template from your Library to share it here."))
                    )
                } else {
                    list
                }
            }
        }
        .navigationTitle(String(localized: "Published by You"))
        .navigationBarTitleDisplayMode(.inline)
        .background { ProBackground() }
        .task { await load() }
    }

    private var list: some View {
        List {
            ForEach(templates) { template in
                row(template)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func row(_ template: CommunityTemplateRowDTO) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(template.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if template.sourceEventCompleted {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption2)
                        .foregroundStyle(ShiftPalette.accent)
                }
                Spacer(minLength: 0)
                if !template.isPublished {
                    Text(String(localized: "Hidden"))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 12) {
                Label("\(template.blockCount)", systemImage: "rectangle.stack")
                Label("\(template.timesApplied)", systemImage: "square.and.arrow.down")
                Text(template.templateCategory.displayName)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await delete(template) }
            } label: {
                Label(String(localized: "Delete"), systemImage: "trash")
            }
            Button {
                Task { await togglePublished(template) }
            } label: {
                if template.isPublished {
                    Label(String(localized: "Hide"), systemImage: "eye.slash")
                } else {
                    Label(String(localized: "Publish"), systemImage: "eye")
                }
            }
            .tint(ShiftPalette.accent)
        }
    }

    // MARK: - Data

    private func load() async {
        guard let service else { phase = .failed(String(localized: "Unavailable")); return }
        do {
            templates = try await service.myTemplates()
            phase = .loaded
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func togglePublished(_ template: CommunityTemplateRowDTO) async {
        guard let service else { return }
        try? await service.setPublished(templateID: template.id, isPublished: !template.isPublished)
        await load()
    }

    private func delete(_ template: CommunityTemplateRowDTO) async {
        guard let service else { return }
        try? await service.softDelete(templateID: template.id)
        await load()
    }
}
