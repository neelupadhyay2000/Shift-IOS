import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import Models

/// Hero countdown component for the active block.
///
/// Fills the available space given to it by the parent (LiveDashboardView).
/// - Block title: 32pt bold.
/// - Countdown: 72pt monospace mm:ss, updating every second via TimelineView.
/// - At 00:00 the timer flips red, counts UP, label becomes "OVERTIME",
///   and a `UINotificationFeedbackGenerator` pulse fires exactly once per transition.
struct ActiveBlockHero: View {

    let block: TimeBlockModel

    /// Tracks whether we have already fired the overtime haptic for this block,
    /// so it only fires once at the transition boundary.
    @State private var overtimeHapticFired = false

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
                .accessibilityAddTraits(.isHeader)

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
                        .animation(.easeInOut(duration: 0.3), value: isOvertime)

                    Text(isOvertime
                         ? String(localized: "OVERTIME")
                         : String(localized: "Remaining"))
                        .font(.caption.weight(.bold))
                        .tracking(2)
                        .foregroundStyle(isOvertime ? Color.red : Color.secondary)
                        .animation(.easeInOut(duration: 0.3), value: isOvertime)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    isOvertime
                        ? String(localized: "Overtime by \(formatCountdown(remaining))")
                        : String(localized: "\(formatCountdown(remaining)) remaining")
                )
                .accessibilityAddTraits(.updatesFrequently)
                // Fire haptic exactly once when we cross the 00:00 boundary
                .onChange(of: isOvertime) { _, isNowOvertime in
                    guard isNowOvertime, !overtimeHapticFired else { return }
                    overtimeHapticFired = true
                    #if canImport(UIKit)
                    let generator = UINotificationFeedbackGenerator()
                    generator.prepare()
                    generator.notificationOccurred(.warning)
                    #endif
                }
            }

            // End-time subtitle
            Label(
                String(localized: "Ends at \(blockEnd, format: .dateTime.hour().minute())"),
                systemImage: "clock"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        // Reset haptic flag if the block changes (e.g. block advanced while still showing hero)
        .onChange(of: block.id) { _, _ in
            overtimeHapticFired = false
        }
    }

    // MARK: - Helpers

    /// Formats a `TimeInterval` as mm:ss (or h:mm:ss for durations ≥ 1 hour).
    /// Works for both positive (countdown) and negative (overtime count-up) values.
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

