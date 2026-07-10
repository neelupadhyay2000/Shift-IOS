import CoreLocation
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
    @Environment(\.waitlistService) private var waitlistService
    @Environment(\.marketplaceLocation) private var location
    @Environment(SupabaseAuthService.self) private var authService
    @Environment(\.colorScheme) private var colorScheme

    @State private var searchText = ""
    @State private var featured: [VendorSearchResultDTO] = []
    @State private var saved: [VendorSearchResultDTO] = []
    @State private var savedIDs: Set<UUID> = []
    @State private var isLoading = true

    /// "Browse all" — the endless grid beneath the merchandised carousels, the way
    /// Facebook Marketplace and Instagram Explore let you just keep scrolling.
    @State private var browse: [VendorSearchResultDTO] = []
    @State private var browseOffset = 0
    @State private var browseReachedEnd = false
    @State private var isLoadingBrowse = false

    private let browsePageSize = 20
    /// How many vendors sit on the Featured shelf. Short on purpose — a shelf of
    /// everything is not a shelf.
    private let featuredCount = 6
    /// Two square cells per row on iPhone; more on iPad.
    private let browseColumns = [GridItem(.adaptive(minimum: 158), spacing: 12)]

    private var coordinate: CLLocationCoordinate2D? { location?.coordinate }

    /// The grid, minus anyone already on the Featured shelf, so a vendor never
    /// appears twice on one screen. Paging still advances on the server's list.
    private var browseVisible: [VendorSearchResultDTO] {
        let featuredIDs = Set(featured.map(\.profileID))
        return browse.filter { !featuredIDs.contains($0.profileID) }
    }

    /// True when the signed-in user joined the waitlist as vendor/both but has
    /// not yet become a vendor — the launch banner's audience (E24 Task 1: the
    /// waitlist-joined banner converts to "Marketplace is live — set up your
    /// profile"). Planner-role members need no banner: the live directory they
    /// are looking at IS the launch.
    @State private var isUnconvertedVendorWaitlister = false
    /// Sticky dismissal so the banner doesn't nag forever; it also disappears
    /// permanently once the user becomes a vendor (the `isVendor` branch).
    @AppStorage("marketplaceLaunchBannerDismissed") private var launchBannerDismissed = false

    private var isVendor: Bool { authService.isVendorAccount }

    private var showsLaunchBanner: Bool {
        isUnconvertedVendorWaitlister && !launchBannerDismissed
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // A vendor sees their pro dashboard then browses; a planner shops.
                if isVendor {
                    VendorDashboardView(onOpenVendorSettings: onOpenVendorSettings)
                    searchField
                    categoryShortcuts
                    featuredSection
                    browseAllSection
                } else {
                    if showsLaunchBanner { launchBanner }
                    searchField
                    categoryShortcuts
                    if !saved.isEmpty { savedSection }
                    featuredSection
                    browseAllSection
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
        // A location fix arriving turns on distances and re-sorts by proximity.
        .onChange(of: coordinate?.latitude) { _, _ in Task { await load() } }
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
            sectionHeader(String(localized: "Saved"))
            carousel(saved)
        }
        .accessibilityIdentifier(AccessibilityID.Marketplace.savedVendorsList)
    }

    // MARK: Category shortcuts

    /// A quick way into a single vendor type — without letting the *type* dictate
    /// how the page is ordered. (This replaces the old per-category carousels,
    /// which grouped the whole home page by vendor type.)
    private var categoryShortcuts: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach([VendorRole.photographer, .dj, .planner, .caterer, .florist], id: \.self) { role in
                    NavigationLink(value: MarketplaceDestination.searchResults(query: "", category: role, onDate: nil)) {
                        HStack(spacing: 6) {
                            Image(systemName: role.systemImage).font(.caption)
                            Text(role.displayName).font(.subheadline.weight(.medium))
                        }
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .foregroundStyle(MarketplaceCategory.color(role.rawValue))
                        .background(ShiftPalette.soft(MarketplaceCategory.color(role.rawValue)), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityIdentifier(AccessibilityID.Marketplace.categoryChips)
    }

    // MARK: Featured

    /// A short editorial shelf at the top of the page, ranked server-side by a
    /// **Bayesian shrunk rating** (`p_sort = 'featured'`) so a single 5-star review
    /// can't outrank a vendor with a long, strong record. Before anyone has reviews
    /// it degrades to most-booked, which is the same trust signal.
    @ViewBuilder
    private var featuredSection: some View {
        if isLoading && featured.isEmpty {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
        } else if !featured.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(String(localized: "Featured"))
                carousel(featured)
            }
            .accessibilityIdentifier(AccessibilityID.Marketplace.featuredList)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title).microLabel()
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

    // MARK: All vendors — the endless grid (Facebook Marketplace / IG Explore)

    /// Everything else, paged, ordered by **completed events** — the app's own
    /// earned trust signal, not a self-declared one. Each cell promotes the
    /// vendor's service so the grid is scannable without reading names.
    @ViewBuilder
    private var browseAllSection: some View {
        if !browseVisible.isEmpty || isLoadingBrowse {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "All vendors")).microLabel()
                        Text(String(localized: "Most events completed first"))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 8)
                    // Location adds distance labels; it no longer reorders the page.
                    if coordinate == nil, location?.isDenied == false {
                        Button { location?.requestLocation() } label: {
                            Label(String(localized: "Show distances"), systemImage: "location")
                                .font(.caption2.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(ShiftPalette.accent)
                    }
                }

                LazyVGrid(columns: browseColumns, spacing: 12) {
                    ForEach(browseVisible) { result in
                        NavigationLink(value: MarketplaceDestination.vendorProfile(profileID: result.profileID)) {
                            VendorCard(
                                result: result,
                                isSaved: savedIDs.contains(result.profileID),
                                onToggleSave: isVendor ? nil : { toggleSave(result.profileID) },
                                style: .grid
                            )
                        }
                        .buttonStyle(.pressableCard)
                        // Page off the last *rendered* cell — the featured filter can
                        // remove the server's last row, which would never appear.
                        .onAppear {
                            if result.id == browseVisible.last?.id { Task { await loadMoreBrowse() } }
                        }
                    }
                }

                if isLoadingBrowse {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
                }
            }
            .accessibilityIdentifier(AccessibilityID.Marketplace.browseAllGrid)
        } else if !isLoading {
            ContentUnavailableView(
                String(localized: "No vendors yet"),
                systemImage: "storefront",
                description: Text(String(localized: "Be the first to list your business — set it up in Settings."))
            )
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

    // MARK: Launch banner (E24 Task 1)

    /// The waitlist-joined banner, converted: "The Marketplace is live — set up
    /// your profile". Shown only to vendor/both waitlisters who haven't become
    /// vendors yet; the CTA is the same vendor-settings deep-link as the nudge.
    private var launchBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            ShiftIconTile(systemImage: "megaphone.fill")
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "The Marketplace is live 🎉"))
                    .font(.subheadline.weight(.semibold))
                Text(String(localized: """
                You're off the waitlist. Set up your vendor profile now and be \
                there when planners start searching.
                """))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    AnalyticsService.send(.marketplaceLaunchBannerTapped)
                    onOpenVendorSettings()
                } label: {
                    Text(String(localized: "Set Up Profile"))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(ShiftPalette.accent, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
            Button {
                launchBannerDismissed = true
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Dismiss"))
        }
        .proCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Marketplace.launchBanner)
    }

    // MARK: Data

    private func load() async {
        guard let service else { isLoading = false; return }
        isLoading = true
        defer { isLoading = false }
        let point = coordinate
        // A short editorial shelf, ranked by the Bayesian shrunk rating. The point
        // is passed only so the cards can show distance — it doesn't reorder.
        featured = (try? await service.searchVendors(
            query: nil, category: nil,
            latitude: point?.latitude, longitude: point?.longitude,
            radiusKm: nil, limit: featuredCount, offset: 0, onDate: nil,
            sort: .featured
        )) ?? []
        // Planners: load their saved shortlist + heart state. (Vendors don't save.)
        if !isVendor {
            saved = (try? await service.savedVendors()) ?? []
            savedIDs = (try? await service.savedVendorIDs()) ?? []
            await refreshLaunchBannerAudience()
        }
        await reloadBrowse()
    }

    /// Resets and refills the endless grid (first page).
    private func reloadBrowse() async {
        browse = []
        browseOffset = 0
        browseReachedEnd = false
        await loadMoreBrowse()
    }

    private func loadMoreBrowse() async {
        guard let service, !browseReachedEnd, !isLoadingBrowse else { return }
        isLoadingBrowse = true
        defer { isLoadingBrowse = false }
        let point = coordinate
        // Everything else, ranked by completed events — the app's own trust signal.
        // The point rides along only to populate distance labels.
        let page = (try? await service.searchVendors(
            query: nil, category: nil,
            latitude: point?.latitude, longitude: point?.longitude,
            radiusKm: nil, limit: browsePageSize, offset: browseOffset, onDate: nil,
            sort: .booked
        )) ?? []
        browse.append(contentsOf: page)
        // `offset` must count what the *server* returned, not what we display —
        // the featured de-duplication below is a view concern only.
        browseOffset += page.count
        if page.count < browsePageSize { browseReachedEnd = true }
    }

    /// One cheap self-row read: the banner targets waitlist vendor/both members
    /// who haven't converted. Skipped entirely once dismissed.
    private func refreshLaunchBannerAudience() async {
        guard !launchBannerDismissed, let waitlistService else { return }
        let entry = try? await waitlistService.currentEntry()
        let role = entry.flatMap { WaitlistInterestRole(rawValue: $0.interestRole) }
        isUnconvertedVendorWaitlister = (role == .vendor || role == .both)
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
