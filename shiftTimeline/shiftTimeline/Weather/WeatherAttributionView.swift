import SwiftUI
import Services

/// Apple Weather™ attribution required by WeatherKit (App Review Guideline 5.2.5).
///
/// Shows the Apple Weather mark and a link to Apple's legal data-sources page.
/// Render this wherever WeatherKit-derived data (rain-risk forecasts) is used so
/// the source is always clear and the legal link is reachable.
///
/// It prefers the official marks/link from WeatherKit's `WeatherAttribution`
/// API, but **always renders** — falling back to the Apple Weather wordmark and
/// the stable legal URL if that fetch is slow or unavailable — so the required
/// attribution is never blank.
struct WeatherAttributionView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var attribution: WeatherService.Attribution?

    /// Stable Apple Weather legal-attribution page, used until (or if) the
    /// WeatherKit API supplies the localized `legalPageURL`.
    private static let fallbackLegalURL = URL(string: "https://weatherkit.apple.com/legal-attribution.html")

    private var legalURL: URL? { attribution?.legalPageURL ?? Self.fallbackLegalURL }

    var body: some View {
        Group {
            if let legalURL {
                Link(destination: legalURL) {
                    HStack(spacing: 6) {
                        mark
                        Text(String(localized: "Other data sources"))
                            .font(.caption2)
                            .underline()
                    }
                    .foregroundStyle(.secondary)
                }
                .accessibilityLabel(String(localized: "Weather data provided by Apple Weather. Opens the list of data sources."))
            }
        }
        .task {
            if attribution == nil {
                attribution = await WeatherService().attribution()
            }
        }
    }

    /// The Apple Weather combined mark when loaded, else the Apple Weather
    /// wordmark text so the trademark is always shown.
    @ViewBuilder
    private var mark: some View {
        if let attribution {
            AsyncImage(
                url: colorScheme == .dark ? attribution.markDarkURL : attribution.markLightURL
            ) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                wordmark
            }
            .frame(height: 16)
        } else {
            wordmark
        }
    }

    /// "\u{F8FF} Weather" — the Apple logo glyph + "Weather".
    private var wordmark: some View {
        Text(verbatim: "\u{F8FF} Weather")
            .font(.caption2.weight(.medium))
    }
}
