import SwiftUI

// Remaining placeholder destination screens for the Marketplace navigation stack.
// MarketplaceHomeView, VendorSearchResultsView, and VendorPublicProfileView are
// now real (own files); these two stay stubs until their stories land:
//   - MyVendorProfileView → the vendor opt-in / profile editor (+ Terms gate)
//   - PortfolioEditorView  → portfolio management
// E11 wires the request inbox.

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
