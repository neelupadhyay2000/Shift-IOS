import Models
import SwiftUI

/// Displays a yellow rain-warning banner for a single outdoor block that has
/// a rain probability above the threshold (> 50%).
///
/// Rendered once per at-risk block by `EventDetailView`. The copy is fixed:
/// "Rain likely during [Block Name] (XX% chance). Consider indoor backup."
struct RainWarningBanner: View {
    let blockTitle: String
    /// Raw probability in 0.0–1.0 range from `BlockRainEntry.rainProbability`.
    let rainProbability: Double

    private var percentage: Int {
        Int((rainProbability * 100).rounded())
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "cloud.rain.fill")
                .foregroundStyle(.yellow)
                .font(.system(size: 18, weight: .semibold))
            Text("Rain likely during \(blockTitle) (\(percentage)% chance). Consider indoor backup.")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.black)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityLabel(
            "Rain warning for \(blockTitle): \(percentage)% chance. Consider indoor backup."
        )
    }
}
