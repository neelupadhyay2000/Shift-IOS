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
                tint: .orange
            )
        }

        if let sunset = sunsetTime {
            markerLine(
                date: sunset,
                label: String(localized: "Sunset"),
                icon: "sunset.fill",
                tint: .red
            )
        }
    }

    // MARK: - Private

    private func markerLine(
        date: Date,
        label: String,
        icon: String,
        tint: Color
    ) -> some View {
        let y = layout.yOffset(for: date)

        return HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(tint)

            Text(date, format: .dateTime.hour().minute())
                .font(.system(size: 9, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tint.opacity(0.8))

            Text("— \(label)", comment: "Em-dash prefix before sunset/golden hour label on timeline ruler")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(tint.opacity(0.6))

            SunsetDashedLine()
                .stroke(
                    tint.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
                .frame(height: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .offset(y: y - 5)
        .allowsHitTesting(false)
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
