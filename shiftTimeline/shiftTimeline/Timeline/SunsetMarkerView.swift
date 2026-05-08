import SwiftUI

/// Non-interactive horizontal markers on the time ruler for golden hour and sunset.
///
/// - **Amber** dashed line at golden hour start, labeled "Golden Hour".
/// - **Red** dashed line at sunset, labeled "Sunset".
///
/// Uses the same overlay pattern as `PinnedAnchorView`.
struct SunsetMarkerView: View {

    let goldenHourStart: Date?
    let sunsetTime: Date?
    let layout: TimeRulerLayout

    var body: some View {
        if let golden = goldenHourStart {
            markerLine(
                date: golden,
                label: String(localized: "Golden Hour"),
                icon: "sun.haze.fill",
                tint: .orange,
                a11yLabel: String(
                    localized: "Golden hour starts at \(golden.formatted(.dateTime.hour().minute()))"
                )
            )
        }

        if let sunset = sunsetTime {
            markerLine(
                date: sunset,
                label: String(localized: "Sunset"),
                icon: "sunset.fill",
                tint: .red,
                a11yLabel: String(
                    localized: "Sunset at \(sunset.formatted(.dateTime.hour().minute()))"
                )
            )
        }
    }

    // MARK: - Private

    private func markerLine(
        date: Date,
        label: String,
        icon: String,
        tint: Color,
        a11yLabel: String
    ) -> some View {
        let y = layout.yOffset(for: date)

        // Layout: a compact pill badge pinned inside the 64pt ruler gutter,
        // followed by the dashed line extending into the block content area.
        // This prevents the label text from floating over block cards.
        return HStack(spacing: 0) {
            // Badge — constrained to the ruler gutter width so it never
            // overlaps with block content to the right.
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 7, weight: .bold))
                Text(date, format: .dateTime.hour().minute())
                    .font(.system(size: 8, weight: .semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(tint.opacity(0.10), in: Capsule())
            .frame(width: 64, alignment: .leading)

            // Dashed rule — begins at the right edge of the ruler gutter
            SunsetDashedLine()
                .stroke(
                    tint.opacity(0.30),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
                .frame(height: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .offset(y: y - 5)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
    }
}

// MARK: - Dashed Line Shape

private struct SunsetDashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
