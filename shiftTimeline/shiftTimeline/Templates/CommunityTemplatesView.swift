import Models
import SwiftUI

/// Community segment of the Templates tab: browse, filter, and apply run-sheets
/// shared by other Shift users.
///
/// Falls back to the coming-soon teaser when the community service isn't wired
/// (offline, sync disabled, previews, tests) so the segment is never blank.
/// Designed as plain content (no `ScrollView`) — `TemplateBrowserView` embeds it
/// under the section picker inside its own scroll view.
struct CommunityTemplatesView: View {

    @Environment(\.communityTemplateService) private var service
    @Environment(\.contentReportService) private var reportService

    @State private var templates: [CommunityTemplateDTO] = []
    @State private var category: TemplateCategory?
    @State private var sort: CommunityTemplateSort = .popular
    @State private var searchText = ""
    @State private var committedSearch = ""
    @State private var phase: Phase = .loading
    @State private var blockedAuthorIDs: Set<UUID> = []

    private enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    /// A stable key for the browse query; changing any facet re-runs the fetch.
    private var queryKey: String {
        "\(category?.rawValue ?? "all")|\(sort.rawValue)|\(committedSearch)"
    }

    /// Blocked authors are filtered client-side (the browse RPC isn't block-aware),
    /// matching the rest of the marketplace.
    private var visibleTemplates: [CommunityTemplateDTO] {
        templates.filter { !blockedAuthorIDs.contains($0.authorID) }
    }

    var body: some View {
        Group {
            if service == nil {
                CommunityTemplatesTeaserView()
            } else {
                content
            }
        }
    }

    private var content: some View {
        VStack(spacing: 16) {
            filterBar

            switch phase {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 220)
            case .failed(let message):
                ContentUnavailableView(
                    String(localized: "Couldn’t Load Templates"),
                    systemImage: "wifi.exclamationmark",
                    description: Text(message)
                )
                .frame(maxWidth: .infinity, minHeight: 220)
            case .loaded:
                if visibleTemplates.isEmpty {
                    ContentUnavailableView(
                        String(localized: "No Community Templates"),
                        systemImage: "person.2.slash",
                        description: Text(String(localized: "Be the first to publish one from your Library."))
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(visibleTemplates) { dto in
                            NavigationLink {
                                CommunityTemplateDetailView(template: dto)
                            } label: {
                                CommunityTemplateCard(template: dto)
                            }
                            .buttonStyle(.pressableCard)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
        }
        .task(id: queryKey) { await reload() }
        .task { await loadBlockedAuthors() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    MyPublishedTemplatesView()
                } label: {
                    Image(systemName: "square.and.arrow.up.on.square")
                }
                .accessibilityLabel(String(localized: "Published by you"))
            }
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(String(localized: "Search templates"), text: $searchText)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onSubmit { committedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        committedSearch = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                Menu {
                    Picker(String(localized: "Sort"), selection: $sort) {
                        ForEach(CommunityTemplateSort.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle")
                        .font(.title3)
                        .foregroundStyle(ShiftPalette.accent)
                }
                .accessibilityLabel(String(localized: "Sort"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .proSurface()
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    categoryChip(title: String(localized: "All"), isSelected: category == nil) {
                        category = nil
                    }
                    ForEach(TemplateCategory.allCases, id: \.self) { item in
                        categoryChip(title: item.displayName, isSelected: category == item) {
                            category = (category == item) ? nil : item
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func categoryChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(isSelected ? ShiftPalette.accent.opacity(0.18) : Color(.tertiarySystemFill))
                )
                .foregroundStyle(isSelected ? ShiftPalette.accent : Color.primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data

    private func reload() async {
        guard let service else { return }
        if templates.isEmpty { phase = .loading }
        do {
            let result = try await service.browse(
                category: category,
                query: committedSearch,
                sort: sort,
                limit: 60,
                offset: 0
            )
            templates = result
            phase = .loaded
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func loadBlockedAuthors() async {
        blockedAuthorIDs = (try? await reportService?.blockedProfileIDs()) ?? []
    }
}

// MARK: - Card

/// One community template in the browse grid: mini timeline, name, author, the
/// verified badge, and the apply count.
private struct CommunityTemplateCard: View {

    let template: CommunityTemplateDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(template.templateCategory.displayName).microLabel()
                Spacer(minLength: 0)
                if template.sourceEventCompleted {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption2)
                        .foregroundStyle(ShiftPalette.accent)
                        .accessibilityLabel(String(localized: "Verified, run in Shift"))
                }
            }

            timelineThumbnail
                .frame(height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(template.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)

            Text(String(localized: "by \(template.authorName)"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 10) {
                Label {
                    Text("\(template.blockCount)").monospacedDigit()
                } icon: {
                    Image(systemName: "rectangle.stack")
                }
                Label {
                    Text("\(template.timesApplied)").monospacedDigit()
                } icon: {
                    Image(systemName: "square.and.arrow.down")
                }
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .proCard(padding: 12)
    }

    private var timelineThumbnail: some View {
        GeometryReader { geometry in
            let total = template.blocks.map { $0.relativeStartOffset + $0.duration }.max() ?? 1
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6).fill(Color(.tertiarySystemFill))
                if total > 0 {
                    ForEach(Array(template.blocks.enumerated()), id: \.offset) { _, block in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: block.colorTag))
                            .frame(
                                width: max(2, geometry.size.width * (block.duration / total)),
                                height: block.isPinned ? 38 : 26
                            )
                            .offset(x: geometry.size.width * (block.relativeStartOffset / total))
                    }
                }
            }
        }
    }
}
