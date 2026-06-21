import Models
import SwiftUI

/// Root of the Marketplace tab — a clean discovery + comms hub. Search & filter
/// the vendor directory, browse by category, and open your unified Inbox
/// (requests + messages). Everything about *your* listing (vendor profile,
/// availability, portfolio, "show me in the marketplace") lives in Settings; a
/// subtle nudge here deep-links non-vendors there.
struct MarketplaceHomeView: View {

    /// The Marketplace stack path, so the search field can push results
    /// programmatically (category chips / cards use NavigationLink(value:)).
    @Binding var path: [MarketplaceDestination]
    /// Switches to the Settings tab (all vendor/listing controls live there).
    var onOpenVendorSettings: () -> Void

    @Environment(\.marketplaceService) private var service
    @Environment(SupabaseAuthService.self) private var authService

    @State private var searchText = ""
    @State private var featured: [VendorSearchResultDTO] = []
    @State private var saved: [VendorSearchResultDTO] = []
    @State private var savedIDs: Set<UUID> = []
    @State private var isLoading = true

    private var isVendor: Bool { authService.isVendorAccount }

    private let categories: [VendorRole] = [.photographer, .dj, .planner, .caterer, .florist]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // Account-type aware: a vendor sees their pro dashboard then browse;
                // a planner shops (search + saved + browse).
                if isVendor {
                    VendorDashboardView(onOpenVendorSettings: onOpenVendorSettings)
                    browseHeader
                    searchSection
                    categorySection
                    featuredSection
                } else {
                    searchSection
                    inboxRow
                    becomeVendorNudge
                    savedSection
                    categorySection
                    featuredSection
                }
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background { ProBackground() }
        .navigationTitle(String(localized: "Marketplace"))
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
        .refreshable { await load() }
    }

    private var browseHeader: some View {
        Text(String(localized: "Browse vendors")).microLabel()
            .padding(.top, 4)
    }

    // MARK: Saved (planner accounts)

    @ViewBuilder
    private var savedSection: some View {
        if !saved.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "Saved vendors")).microLabel()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(saved) { result in
                            NavigationLink(value: MarketplaceDestination.vendorProfile(profileID: result.profileID)) {
                                VendorCard(result: result, isSaved: true, onToggleSave: { toggleSave(result.profileID) })
                                    .frame(width: 260)
                            }
                            .buttonStyle(.pressableCard)
                        }
                    }
                    .padding(.bottom, 2)
                }
            }
            .accessibilityIdentifier(AccessibilityID.Marketplace.savedVendorsList)
        }
    }

    // MARK: Search

    private var searchSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(String(localized: "Search vendors"), text: $searchText)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit { runSearch() }
                .accessibilityIdentifier(AccessibilityID.Marketplace.searchField)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .proCard(padding: 14)
    }

    private func runSearch() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        path.append(.searchResults(query: trimmed, category: nil, onDate: nil))
    }

    // MARK: Inbox (requests + messages)

    private var inboxRow: some View {
        NavigationLink(value: MarketplaceDestination.inbox) {
            toolRow(
                icon: "tray.full.fill",
                title: String(localized: "Inbox"),
                subtitle: String(localized: "Event requests & messages"),
                showsChevron: true
            )
        }
        .buttonStyle(.pressableCard)
        .accessibilityIdentifier(AccessibilityID.Marketplace.inbox)
    }

    // MARK: Become-a-vendor nudge (deep-links to Settings)

    private var becomeVendorNudge: some View {
        Button { onOpenVendorSettings() } label: {
            HStack(spacing: 12) {
                Image(systemName: "storefront.fill")
                    .foregroundStyle(ShiftPalette.accent)
                    .frame(width: 36, height: 36)
                    .background(ShiftPalette.soft(ShiftPalette.accent), in: RoundedRectangle(cornerRadius: ShiftDesign.iconRadius, style: .continuous))
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

    // MARK: Categories

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Browse by category")).microLabel()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(categories, id: \.self) { role in
                        NavigationLink(value: MarketplaceDestination.searchResults(query: "", category: role, onDate: nil)) {
                            let color = ShiftDesign.roleColor(for: role)
                            HStack(spacing: 6) {
                                Image(systemName: role.systemImage).font(.caption)
                                Text(role.displayName).font(.subheadline.weight(.medium))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .foregroundStyle(color)
                            .background(ShiftPalette.soft(color), in: Capsule())
                        }
                        .buttonStyle(.pressableCard)
                    }
                }
                .padding(.vertical, 2)
            }
            .accessibilityIdentifier(AccessibilityID.Marketplace.categoryChips)
        }
    }

    // MARK: Featured

    private var featuredSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Featured vendors")).microLabel()
            if isLoading {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
            } else if featured.isEmpty {
                ContentUnavailableView(
                    String(localized: "No vendors yet"),
                    systemImage: "storefront",
                    description: Text(String(localized: "Be the first to list your business — set it up in Settings."))
                )
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 12)], spacing: 12) {
                    ForEach(featured) { result in
                        NavigationLink(value: MarketplaceDestination.vendorProfile(profileID: result.profileID)) {
                            VendorCard(
                                result: result,
                                isSaved: savedIDs.contains(result.profileID),
                                onToggleSave: isVendor ? nil : { toggleSave(result.profileID) }
                            )
                        }
                        .buttonStyle(.pressableCard)
                    }
                }
                .accessibilityIdentifier(AccessibilityID.Marketplace.featuredList)
            }
        }
    }

    private func toolRow(icon: String, title: String, subtitle: String, showsChevron: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .foregroundStyle(ShiftPalette.accent)
                .frame(width: 36, height: 36)
                .background(ShiftPalette.soft(ShiftPalette.accent), in: RoundedRectangle(cornerRadius: ShiftDesign.iconRadius, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .proCard()
        .contentShape(Rectangle())
    }

    // MARK: Data

    private func load() async {
        guard let service else { isLoading = false; return }
        isLoading = true
        defer { isLoading = false }
        featured = (try? await service.searchVendors(
            query: nil, category: nil, latitude: nil, longitude: nil,
            radiusKm: nil, limit: 10, offset: 0, onDate: nil, sort: nil
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
