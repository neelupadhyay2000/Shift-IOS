import SwiftUI

/// Persistent banner showing a live countdown to golden hour or sunset.
///
/// Color rules:
/// - **Default:** secondary style (golden hour > 60 min away)
/// - **Amber:** golden hour is < 60 minutes away
/// - **Red:** sunset is < 30 minutes away
///
/// When both golden hour and sunset have passed, the banner hides itself.
struct SunsetBanner: View {

    let sunsetTime: Date
    let goldenHourStart: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let toGolden = goldenHourStart.timeIntervalSince(now)
            let toSunset = sunsetTime.timeIntervalSince(now)

            if toSunset > 0 {
                let (label, tint) = displayState(
                    toGolden: toGolden,
                    toSunset: toSunset
                )

                HStack(spacing: 6) {
                    Image(systemName: "sun.horizon.fill")
                        .imageScale(.small)

                    Text(label)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                }
                .foregroundStyle(tint)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(tint.opacity(0.15), in: Capsule())
            }
        }
    }

    // MARK: - Helpers

    private func displayState(
        toGolden: TimeInterval,
        toSunset: TimeInterval
    ) -> (String, Color) {
        if toSunset < 30 * 60 {
            // < 30 min to sunset → red
            return (
                String(localized: "Sunset in \(formatCountdown(toSunset))"),
                .red
            )
        } else if toGolden < 60 * 60 && toGolden > 0 {
            // < 60 min to golden hour → amber
            return (
                String(localized: "Golden Hour in \(formatCountdown(toGolden))"),
                .orange
            )
        } else if toGolden <= 0 {
            // Golden hour has started, counting down to sunset
            return (
                String(localized: "Sunset in \(formatCountdown(toSunset))"),
                .orange
            )
        } else {
            // Still far away → default
            return (
                String(localized: "Golden Hour in \(formatCountdown(toGolden))"),
                .secondary
            )
        }
    }

    private func formatCountdown(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.towardZero))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}
