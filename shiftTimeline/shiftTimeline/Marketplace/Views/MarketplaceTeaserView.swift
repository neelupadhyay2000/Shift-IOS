import SwiftUI

/// Root view of the Marketplace tab — teases the upcoming vendor marketplace
/// and captures waitlist demand ahead of launch.
///
/// SHIFT-714: minimal stub so the tab wiring builds. The full teaser UI
/// (hero pitch, Verified-by-Shift preview cards, waitlist CTA + signup sheet)
/// lands in SHIFT-715.
struct MarketplaceTeaserView: View {

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "storefront")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(String(localized: "Find verified vendors. Get found for your work."))
                .font(.title2)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { WarmBackground() }
        .navigationTitle(String(localized: "Marketplace"))
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Previews

#Preview {
    NavigationStack {
        MarketplaceTeaserView()
    }
}
