import SwiftUI

/// Apple WeatherKit attribution, required by App Store Review Guideline 5.2.5.
///
/// WeatherKit apps must visibly display the Apple Weather trademark ( Weather)
/// and link to Apple's legal-attribution page — which lists the underlying data
/// sources — wherever WeatherKit-derived data is presented to the user.
///
/// Rendered by `EventDetailView` whenever an event has a cached weather snapshot
/// (i.e. whenever the rain-risk information derived from WeatherKit is on screen).
struct WeatherAttributionView: View {

    /// Apple's required legal-attribution destination, listing every data source
    /// behind the forecast. Tapping the attribution opens this page.
    private static let legalAttributionURL = URL(
        string: "https://weatherkit.apple.com/legal-attribution.html"
    )!

    var body: some View {
        HStack(spacing: 6) {
            // The Apple Weather trademark:  Weather
            HStack(spacing: 3) {
                Image(systemName: "apple.logo")
                    .imageScale(.small)
                Text(verbatim: "Weather")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(verbatim: "·")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Legal source link required by the attribution guidelines.
            Link(destination: Self.legalAttributionURL) {
                Text(String(localized: "Other data sources"))
                    .font(.caption)
                    .underline()
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            String(localized: "Weather data provided by Apple Weather. Double tap to view other data sources.")
        )
    }
}

#Preview {
    WeatherAttributionView()
}
