import SwiftUI

// Placeholder destination screens for the Marketplace navigation stack.
//
// This story wires routing (MarketplaceDestination + deep links) ahead of the
// directory UI. Each screen is a minimal, compiling stub that the directory-UI
// story replaces with the real browse / profile / editor views. VendorPublic
// ProfileView already mounts the UGC safety menu so the report/block path is
// functional end-to-end the moment a profile can be reached.

/// A vendor's public profile (deep-link + search-result target).
struct VendorPublicProfileView: View {
    let profileID: UUID
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        MarketplacePlaceholder(
            title: String(localized: "Vendor profile"),
            systemImage: "person.crop.square"
        )
        .navigationTitle(String(localized: "Vendor"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                VendorSafetyMenu(
                    subjectProfileID: profileID,
                    subjectName: String(localized: "this vendor"),
                    contentType: .vendorProfile,
                    onBlocked: { dismiss() }
                )
            }
        }
    }
}

/// The vendor directory search results list.
struct VendorSearchResultsView: View {
    var body: some View {
        MarketplacePlaceholder(
            title: String(localized: "Search vendors"),
            systemImage: "magnifyingglass"
        )
        .navigationTitle(String(localized: "Search"))
    }
}

/// The signed-in user's own vendor profile (opt-in + overview).
struct MyVendorProfileView: View {
    var body: some View {
        MarketplacePlaceholder(
            title: String(localized: "My vendor profile"),
            systemImage: "storefront"
        )
        .navigationTitle(String(localized: "My profile"))
    }
}

/// Portfolio editor for the signed-in vendor.
struct PortfolioEditorView: View {
    var body: some View {
        MarketplacePlaceholder(
            title: String(localized: "Portfolio"),
            systemImage: "photo.on.rectangle.angled"
        )
        .navigationTitle(String(localized: "Portfolio"))
    }
}

// MARK: - Shared placeholder chrome

private struct MarketplacePlaceholder: View {
    let title: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(String(localized: "Coming soon."))
        }
        .background { ProBackground() }
    }
}
