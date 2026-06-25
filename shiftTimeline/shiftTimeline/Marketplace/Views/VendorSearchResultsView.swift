import Models
import SwiftUI

/// Paginated vendor directory results — photo-forward cards with a Filters & Sort
/// sheet (category, available-on date, ordering). Planners can save vendors from
/// each card. Each card pushes the vendor's public profile.
struct VendorSearchResultsView: View {

    @Environment(\.marketplaceService) private var service
    @Environment(SupabaseAuthService.self) private var authService

    @State private var query: String
    @State private var selectedCategory: VendorRole?
    @State private var selectedDate: Date?
    @State private var sort: VendorSort = .rating
    @State private var results: [VendorSearchResultDTO] = []
    @State private var savedIDs: Set<UUID> = []
    @State private var isLoading = false
    @State private var reachedEnd = false
    @State private var offset = 0
    @State private var didInitialLoad = false
    @State private var isShowingFilters = false

    private let pageSize = 20
    private let columns = [GridItem(.adaptive(minimum: 320), spacing: 12)]

    private var canSave: Bool { !authService.isVendorAccount }
    private var activeFilterCount: Int { (selectedCategory != nil ? 1 : 0) + (selectedDate != nil ? 1 : 0) }

    init(initialQuery: String = "", initialCategory: VendorRole? = nil, initialDate: Date? = nil) {
        _query = State(initialValue: initialQuery)
        _selectedCategory = State(initialValue: initialCategory)
        _selectedDate = State(initialValue: initialDate)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                searchField
                filterBar
                resultsList
            }
            .padding(20)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background { ProBackground() }
        .navigationTitle(String(localized: "Search"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !didInitialLoad else { return }
            didInitialLoad = true
            if canSave, let service { savedIDs = (try? await service.savedVendorIDs()) ?? [] }
            await runSearch(reset: true)
        }
        .sheet(isPresented: $isShowingFilters) { filtersSheet }
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

    // MARK: Filter / sort bar

    private var filterBar: some View {
        HStack(spacing: 10) {
            Button { isShowingFilters = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                    Text(activeFilterCount > 0 ? String(localized: "Filters · \(activeFilterCount)") : String(localized: "Filters"))
                        .font(.subheadline.weight(.medium))
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .foregroundStyle(activeFilterCount > 0 ? .white : ShiftPalette.accent)
                .background(activeFilterCount > 0 ? AnyShapeStyle(ShiftPalette.accent) : AnyShapeStyle(ShiftPalette.soft(ShiftPalette.accent)), in: Capsule())
            }
            .buttonStyle(.pressableCard)
            .accessibilityIdentifier(AccessibilityID.Marketplace.filtersButton)

            Menu {
                Picker(String(localized: "Sort"), selection: $sort) {
                    ForEach(VendorSort.allCases) { option in Text(option.label).tag(option) }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.arrow.down")
                    Text(sort.label).font(.subheadline.weight(.medium))
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .foregroundStyle(ShiftPalette.accent)
                .background(ShiftPalette.soft(ShiftPalette.accent), in: Capsule())
            }
            .onChange(of: sort) { _, _ in Task { await runSearch(reset: true) } }

            Spacer(minLength: 0)
        }
    }

    private var filtersSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Category — pill chips (matches the reference).
                    VStack(alignment: .leading, spacing: 10) {
                        Text(String(localized: "Category")).microLabel()
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                categoryChip(nil, label: String(localized: "All"), systemImage: nil)
                                ForEach([VendorRole.photographer, .dj, .planner, .caterer, .florist], id: \.self) { role in
                                    categoryChip(role, label: role.displayName, systemImage: role.systemImage)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    // Availability — toggle + a month calendar (single date; our
                    // backend's `p_on_date` is a single day, not a range).
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: Binding(
                            get: { selectedDate != nil },
                            set: { selectedDate = $0 ? (selectedDate ?? Date()) : nil }
                        )) {
                            Text(String(localized: "Available on a date")).microLabel()
                        }
                        if selectedDate != nil {
                            DatePicker(
                                String(localized: "Available on"),
                                selection: Binding(get: { selectedDate ?? Date() }, set: { selectedDate = $0 }),
                                displayedComponents: .date
                            )
                            .datePickerStyle(.graphical)
                            .tint(ShiftPalette.accent)
                            .proCard(padding: 8)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background { ProBackground() }
            .navigationTitle(String(localized: "Filters"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Clear")) { selectedCategory = nil; selectedDate = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Apply")) { isShowingFilters = false; Task { await runSearch(reset: true) } }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Selectable category pill — indigo when selected, quiet neutral otherwise.
    private func categoryChip(_ role: VendorRole?, label: String, systemImage: String?) -> some View {
        let isSelected = selectedCategory == role
        return Button {
            selectedCategory = role
        } label: {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage).font(.caption) }
                Text(label).font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .foregroundStyle(isSelected ? ShiftPalette.accent : .secondary)
            .background(
                isSelected ? ShiftPalette.soft(ShiftPalette.accent) : ShiftPalette.soft(ShiftPalette.neutral),
                in: Capsule()
            )
            .overlay(Capsule().strokeBorder(isSelected ? ShiftPalette.accent : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Results

    @ViewBuilder
    private var resultsList: some View {
        if isLoading, results.isEmpty {
            SkeletonGrid(columns: columns)
        } else if results.isEmpty {
            ContentUnavailableView(
                String(localized: "No vendors found"),
                systemImage: "magnifyingglass",
                description: Text(String(localized: "Try a different search, category, or date."))
            )
            .padding(.top, 24)
        } else {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(results) { result in
                    NavigationLink(value: MarketplaceDestination.vendorProfile(profileID: result.profileID)) {
                        VendorCard(
                            result: result,
                            isSaved: savedIDs.contains(result.profileID),
                            onToggleSave: canSave ? { toggleSave(result.profileID) } : nil
                        )
                    }
                    .buttonStyle(.pressableCard)
                    .onAppear { if result.id == results.last?.id { Task { await loadMore() } } }
                }
            }
            .accessibilityIdentifier(AccessibilityID.Marketplace.searchResultsList)

            if isLoading { ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12) }
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
            limit: pageSize, offset: offset, onDate: selectedDate, sort: sort
        )) ?? []
        results.append(contentsOf: page)
        offset += page.count
        if page.count < pageSize { reachedEnd = true }
    }

    private func loadMore() async {
        guard !reachedEnd, !isLoading else { return }
        await runSearch(reset: false)
    }

    private func toggleSave(_ id: UUID) {
        guard let service else { return }
        let wasSaved = savedIDs.contains(id)
        if wasSaved { savedIDs.remove(id) } else { savedIDs.insert(id) }
        Haptics.tap()
        Task {
            do {
                if wasSaved { try await service.unsaveVendor(profileID: id) }
                else { try await service.saveVendor(profileID: id) }
            } catch {
                // Revert on failure.
                if wasSaved { savedIDs.insert(id) } else { savedIDs.remove(id) }
            }
        }
    }
}
