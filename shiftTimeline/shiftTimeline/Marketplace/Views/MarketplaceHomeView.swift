import Models
import SwiftUI

/// Root of the Marketplace tab — a clean discovery hub matching the reference:
/// a large title, a pill search with a filter affordance, and category sections
/// of horizontal, photo-forward vendor carousels ("View All" per category). The
/// unified Inbox is a toolbar action; everything about *your* listing lives in
/// Settings (a nudge deep-links non-vendors there).
struct MarketplaceHomeView: View {

    /// The Marketplace stack path, so search / filters / inbox can push.
    @Binding var path: [MarketplaceDestination]
    /// Switches to the Settings tab (all vendor/listing controls live there).
    var onOpenVendorSettings: () -> Void

    @Environment(\.marketplaceService) private var service
    @Environment(SupabaseAuthService.self) private var authService
    @Environment(\.colorScheme) private var colorScheme

    @State private var searchText = ""
    @State private var featured: [VendorSearchResultDTO] = []
    @State private var saved: [VendorSearchResultDTO] = []
    @State private var savedIDs: Set<UUID> = []
    @State private var isLoading = true

    private var isVendor: Bool { authService.isVendorAccount }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // A vendor sees their pro dashboard then browses; a planner shops.
                if isVendor {
                    VendorDashboardView(onOpenVendorSettings: onOpenVendorSettings)
                    searchField
                    categoryCarousels
                } else {
                    searchField
                    if !saved.isEmpty { savedSection }
                    categoryCarousels
                    becomeVendorNudge
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background { ProBackground() }
        .navigationTitle(String(localized: "Marketplace"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !isVendor {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { path.append(.inbox) } label: {
                        Image(systemName: "tray.full")
                    }
                    .accessibilityIdentifier(AccessibilityID.Marketplace.inbox)
                    .accessibilityLabel(String(localized: "Inbox"))
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Search (pill + filter)

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(String(localized: "Find venues, services, experts…"), text: $searchText)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit { runSearch() }
                .accessibilityIdentifier(AccessibilityID.Marketplace.searchField)
            Button {
                // The filter affordance opens the results screen, where the
                // Filters & Sort sheet (category / date / ordering) lives.
                path.append(.searchResults(
                    query: searchText.trimmingCharacters(in: .whitespacesAndNewlines),
                    category: nil, onDate: nil
                ))
            } label: {
                Image(systemName: "slider.horizontal.3").foregroundStyle(ShiftPalette.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Filters"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white, in: Capsule())
        .overlay(
            Capsule().strokeBorder(
                colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.07),
                lineWidth: 1
            )
        )
    }

    private func runSearch() {
        path.append(.searchResults(
            query: searchText.trimmingCharacters(in: .whitespacesAndNewlines),
            category: nil, onDate: nil
        ))
    }

    // MARK: Saved (planner accounts)

    private var savedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(String(localized: "Saved"), category: nil)
            carousel(saved)
        }
        .accessibilityIdentifier(AccessibilityID.Marketplace.savedVendorsList)
    }

    // MARK: Category carousels (the reference's main content)

    /// Featured vendors grouped into per-category carousels, ordered by category
    /// name so the sections are stable across reloads.
    private var groupedByCategory: [(category: String, vendors: [VendorSearchResultDTO])] {
        Dictionary(grouping: featured, by: { $0.category })
            .map { (category: $0.key, vendors: $0.value) }
            .sorted { MarketplaceCategory.label($0.category) < MarketplaceCategory.label($1.category) }
    }

    @ViewBuilder
    private var categoryCarousels: some View {
        if isLoading {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
        } else if featured.isEmpty {
            ContentUnavailableView(
                String(localized: "No vendors yet"),
                systemImage: "storefront",
                description: Text(String(localized: "Be the first to list your business — set it up in Settings."))
            )
        } else {
            ForEach(groupedByCategory, id: \.category) { group in
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader(MarketplaceCategory.label(group.category), category: MarketplaceCategory.role(group.category))
                    carousel(group.vendors)
                }
            }
            .accessibilityIdentifier(AccessibilityID.Marketplace.featuredList)
        }
    }

    private func sectionHeader(_ title: String, category: VendorRole?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).microLabel()
            Spacer(minLength: 8)
            if let category {
                NavigationLink(value: MarketplaceDestination.searchResults(query: "", category: category, onDate: nil)) {
                    Text(String(localized: "View All"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ShiftPalette.accent)
                }
            }
        }
    }

    private func carousel(_ vendors: [VendorSearchResultDTO]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(vendors) { result in
                    NavigationLink(value: MarketplaceDestination.vendorProfile(profileID: result.profileID)) {
                        VendorCard(
                            result: result,
                            isSaved: savedIDs.contains(result.profileID),
                            onToggleSave: isVendor ? nil : { toggleSave(result.profileID) }
                        )
                        .frame(width: 300)
                    }
                    .buttonStyle(.pressableCard)
                }
            }
            .padding(.bottom, 2)
        }
    }

    // MARK: Become-a-vendor nudge (deep-links to Settings)

    private var becomeVendorNudge: some View {
        Button { onOpenVendorSettings() } label: {
            HStack(spacing: 12) {
                ShiftIconTile(systemImage: "storefront.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Offer your services?")).font(.subheadline.weight(.semibold))
                    Text(String(localized: "Switch to a vendor account in Settings.")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.forward").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .proCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableCard)
        .accessibilityIdentifier(AccessibilityID.Marketplace.becomeVendorButton)
    }

    // MARK: Data

    private func load() async {
        guard let service else { isLoading = false; return }
        isLoading = true
        defer { isLoading = false }
        featured = (try? await service.searchVendors(
            query: nil, category: nil, latitude: nil, longitude: nil,
            radiusKm: nil, limit: 24, offset: 0, onDate: nil, sort: nil
        )) ?? []
        // Planners: load their saved shortlist + heart state. (Vendors don't save.)
        if !isVendor {
            saved = (try? await service.savedVendors()) ?? []
            savedIDs = (try? await service.savedVendorIDs()) ?? []
        }
    }

    private func toggleSave(_ id: UUID) {
        guard let service else { return }
        let wasSaved = savedIDs.contains(id)
        if wasSaved { savedIDs.remove(id) } else { savedIDs.insert(id) }
        Haptics.tap()
        Task {
            do {
                if wasSaved {
                    try await service.unsaveVendor(profileID: id)
                    saved.removeAll { $0.profileID == id }
                } else {
                    try await service.saveVendor(profileID: id)
                    saved = (try? await service.savedVendors()) ?? saved
                }
            } catch {
                if wasSaved { savedIDs.insert(id) } else { savedIDs.remove(id) }
            }
        }
    }
}
