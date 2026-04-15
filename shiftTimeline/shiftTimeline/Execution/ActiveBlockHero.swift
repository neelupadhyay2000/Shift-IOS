import SwiftUI
import Models

/// Hero countdown component for the active block.
///
/// Fills the available space given to it by the parent (LiveDashboardView).
/// Block title: 32pt bold. Countdown: 72pt monospace mm:ss. End-time subtitle below.
/// Timer updates every second via TimelineView — never Combine Timer.publish.
struct ActiveBlockHero: View {

    let block: TimeBlockModel

    private var blockEnd: Date {
        block.scheduledStart.addingTimeInterval(block.duration)
    }

    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            // Block title — 32pt bold
            Text(block.title)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.65)
                .padding(.horizontal, 20)

            // Countdown — 72pt monospace, per-second via TimelineView
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = blockEnd.timeIntervalSince(context.date)
                let isOvertime = remaining < 0

                VStack(spacing: 6) {
                    Text(formatCountdown(remaining))
                        .font(.system(size: 72, weight: .bold, design: .monospaced))
                        .foregroundStyle(isOvertime ? Color.red : Color.primary)
                        .contentTransition(.numericText())
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)

                    if isOvertime {
                        Text(String(localized: "OVERTIME"))
                            .font(.caption.weight(.bold))
                            .tracking(3)
                            .foregroundStyle(.red)
                    }
                }
            }

            // End-time subtitle
            Label(
                String(localized: "Ends at \(blockEnd, format: .dateTime.hour().minute())"),
                systemImage: "clock"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func formatCountdown(_ seconds: TimeInterval) -> String {
        let total = Int(abs(seconds.rounded(.towardZero)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

