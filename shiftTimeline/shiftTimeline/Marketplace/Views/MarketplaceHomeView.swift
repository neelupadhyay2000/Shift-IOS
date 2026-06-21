import Models
import SwiftUI

/// Root of the Marketplace tab — replaces the launch teaser now that the vendor
/// directory is live. Surfaces search, category browse, featured vendors, the
/// "Become a vendor" CTA, and (for vendors) an entry into their tools / request
/// inbox.
struct MarketplaceHomeView: View {

    /// The Marketplace stack path, so the search field can push results
    /// programmatically (category chips / cards use NavigationLink(value:)).
    @Binding var path: [MarketplaceDestination]

    @Environment(\.marketplaceService) private var service
    @Environment(\.waitlistService) private var waitlistService

    @State private var searchText = ""
    @State private var featured: [VendorSearchResultDTO] = []
    @State private var hasVendorProfile = false
    @State private var showVendorWaitlistBanner = false
    @State private var isLoading = true

    private let categories: [VendorRole] = [.photographer, .dj, .planner, .caterer, .florist]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if showVendorWaitlistBanner { vendorWaitlistBanner }
                searchSection
                categorySection
                if hasVendorProfile { vendorToolsSection } else { becomeVendorCTA }
                myRequestsRow
                featuredSection
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

    // MARK: Waitlist tie-in

    private var vendorWaitlistBanner: some View {
        NavigationLink(value: MarketplaceDestination.myVendorProfile) {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.title3).foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(ShiftPalette.accent.gradient, in: RoundedRectangle(cornerRadius: ShiftDesign.iconRadius, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "The marketplace is here"))
                        .font(.subheadline.weight(.semibold))
                    Text(String(localized: "You joined the vendor waitlist — complete your profile to get listed."))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .proCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableCard)
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

    // MARK: Become a vendor

    private var becomeVendorCTA: some View {
        NavigationLink(value: MarketplaceDestination.myVendorProfile) {
            HStack(spacing: 14) {
                Image(systemName: "storefront.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(ShiftPalette.accent.gradient, in: RoundedRectangle(cornerRadius: ShiftDesign.iconRadius, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Become a vendor"))
                        .font(.headline)
                    Text(String(localized: "List your business and get found for events you run in Shift."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .proCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableCard)
        .accessibilityIdentifier(AccessibilityID.Marketplace.becomeVendorButton)
    }

    // MARK: Vendor tools (vendor-mode users)

    private var vendorToolsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Your vendor tools")).microLabel()
            VStack(spacing: 12) {
                NavigationLink(value: MarketplaceDestination.myVendorProfile) {
                    toolRow(icon: "storefront.fill", title: String(localized: "My vendor profile"),
                            subtitle: String(localized: "Edit your listing and portfolio"), showsChevron: true)
                }
                .buttonStyle(.pressableCard)

                // Request inbox (vendor): requests addressed to me.
                NavigationLink(value: MarketplaceDestination.requestInbox) {
                    toolRow(icon: "tray.full.fill", title: String(localized: "Event requests"),
                            subtitle: String(localized: "Requests for your services"), showsChevron: true)
                }
                .buttonStyle(.pressableCard)
                .accessibilityIdentifier(AccessibilityID.Marketplace.requestsInbox)
            }
        }
    }

    // MARK: My requests (planner)

    private var myRequestsRow: some View {
        NavigationLink(value: MarketplaceDestination.myRequests) {
            toolRow(icon: "paperplane.fill", title: String(localized: "My requests"),
                    subtitle: String(localized: "Requests you've sent to vendors"), showsChevron: true)
        }
        .buttonStyle(.pressableCard)
    }

    private func toolRow(icon: String, title: String, subtitle: String, showsChevron: Bool, trailing: AnyView? = nil) -> some View {
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
            if let trailing { trailing }
            if showsChevron {
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .proCard()
        .contentShape(Rectangle())
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
                    description: Text(String(localized: "Be the first to list your business."))
                )
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 12)], spacing: 12) {
                    ForEach(featured) { result in
                        NavigationLink(value: MarketplaceDestination.vendorProfile(profileID: result.profileID)) {
                            VendorCard(result: result)
                        }
                        .buttonStyle(.pressableCard)
                    }
                }
                .accessibilityIdentifier(AccessibilityID.Marketplace.featuredList)
            }
        }
    }

    // MARK: Data

    private func load() async {
        guard let service else { isLoading = false; return }
        isLoading = true
        defer { isLoading = false }
        featured = (try? await service.searchVendors(
            query: nil, category: nil, latitude: nil, longitude: nil,
            radiusKm: nil, limit: 10, offset: 0, onDate: nil
        )) ?? []
        let mine = try? await service.fetchMyVendorProfile()
        hasVendorProfile = (mine ?? nil) != nil

        // Waitlist tie-in: prompt vendor-side waitlist joiners who haven't built a
        // profile yet to complete one.
        showVendorWaitlistBanner = false
        if !hasVendorProfile, let waitlistService,
           let entry = try? await waitlistService.currentEntry() {
            let role = WaitlistInterestRole(rawValue: entry.interestRole)
            showVendorWaitlistBanner = (role == .vendor || role == .both)
        }
    }
}
