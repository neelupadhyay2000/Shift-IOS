import Models
import SwiftUI

/// Paginated vendor directory results. Seeded from the home search field / a
/// category chip, with its own search field + category filter so the query can be
/// refined in place. Each row pushes the vendor's public profile.
struct VendorSearchResultsView: View {

    @Environment(\.marketplaceService) private var service

    @State private var query: String
    @State private var selectedCategory: VendorRole?
    @State private var results: [VendorSearchResultDTO] = []
    @State private var isLoading = false
    @State private var reachedEnd = false
    @State private var offset = 0
    @State private var didInitialLoad = false

    private let pageSize = 20
    private let categories: [VendorRole] = [.photographer, .dj, .planner, .caterer, .florist]

    init(initialQuery: String = "", initialCategory: VendorRole? = nil) {
        _query = State(initialValue: initialQuery)
        _selectedCategory = State(initialValue: initialCategory)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                searchField
                categoryFilter
                resultsList
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background { ProBackground() }
        .navigationTitle(String(localized: "Search"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !didInitialLoad else { return }
            didInitialLoad = true
            await runSearch(reset: true)
        }
    }

    // MARK: Search field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(String(localized: "Search vendors"), text: $query)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit { Task { await runSearch(reset: true) } }
                .accessibilityIdentifier(AccessibilityID.Marketplace.searchField)
            if !query.isEmpty {
                Button { query = ""; Task { await runSearch(reset: true) } } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .proCard(padding: 12)
    }

    // MARK: Category filter

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(role: nil, label: String(localized: "All"))
                ForEach(categories, id: \.self) { role in
                    filterChip(role: role, label: role.displayName)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func filterChip(role: VendorRole?, label: String) -> some View {
        let isSelected = selectedCategory == role
        let color = role.map { ShiftDesign.roleColor(for: $0) } ?? ShiftPalette.accent
        return Button {
            selectedCategory = role
            Task { await runSearch(reset: true) }
        } label: {
            Text(label)
                .font(.subheadline.weight(isSelected ? .semibold : .medium))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .foregroundStyle(isSelected ? .white : color)
                .background(isSelected ? AnyShapeStyle(color.gradient) : AnyShapeStyle(ShiftPalette.soft(color)), in: Capsule())
        }
        .buttonStyle(.pressableCard)
    }

    // MARK: Results

    @ViewBuilder
    private var resultsList: some View {
        if isLoading, results.isEmpty {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
        } else if results.isEmpty {
            ContentUnavailableView(
                String(localized: "No vendors found"),
                systemImage: "magnifyingglass",
                description: Text(String(localized: "Try a different search or category."))
            )
            .padding(.top, 24)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 12)], spacing: 12) {
                ForEach(results) { result in
                    NavigationLink(value: MarketplaceDestination.vendorProfile(profileID: result.profileID)) {
                        VendorCard(result: result)
                    }
                    .buttonStyle(.pressableCard)
                    .onAppear {
                        if result.id == results.last?.id { Task { await loadMore() } }
                    }
                }
            }
            .accessibilityIdentifier(AccessibilityID.Marketplace.searchResultsList)

            if isLoading {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
            }
        }
    }

    // MARK: Data

    private func runSearch(reset: Bool) async {
        guard let service else { return }
        if reset { offset = 0; reachedEnd = false; results = [] }
        guard !reachedEnd, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let page = (try? await service.searchVendors(
            query: trimmed.isEmpty ? nil : trimmed,
            category: selectedCategory,
            latitude: nil, longitude: nil, radiusKm: nil,
            limit: pageSize, offset: offset
        )) ?? []
        results.append(contentsOf: page)
        offset += page.count
        if page.count < pageSize { reachedEnd = true }
    }

    private func loadMore() async {
        guard !reachedEnd, !isLoading else { return }
        await runSearch(reset: false)
    }
}
