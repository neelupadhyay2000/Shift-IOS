import SwiftUI
import Models

struct ContentView: View {

    @Environment(WatchSessionManager.self) private var sessionManager

    var body: some View {
        if let context = sessionManager.currentContext, context.isLive {
            liveView(context)
        } else {
            idleView
        }
    }

    // MARK: - Live

    private func liveView(_ context: WatchContext) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                // Event title
                Text(context.eventTitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                // ── Section 1: Current Block ────────────────────────
                currentBlockSection(context)

                Divider()

                // ── Section 2: Next Block ───────────────────────────
                nextBlockSection(context)

                // ── Section 3: Sunset ───────────────────────────────
                if let sunset = context.sunsetTime, sunset > .now {
                    Divider()
                    sunsetSection(sunset)
                }

                // Status indicators
                if sessionManager.isCommandQueued {
                    Text(String(localized: "Shift queued, will apply when connected"))
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }

                if let error = sessionManager.lastError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }

                Divider()

                // Shift buttons
                HStack(spacing: 12) {
                    Button {
                        sessionManager.sendShiftCommand(minutes: 5)
                    } label: {
                        Text("+5m")
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)

                    Button {
                        sessionManager.sendShiftCommand(minutes: 15)
                    } label: {
                        Text("+15m")
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Section 1: Current Block

    private func currentBlockSection(_ context: WatchContext) -> some View {
        VStack(spacing: 4) {
            Text(context.activeBlockTitle)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let remaining = context.activeBlockEndTime.timeIntervalSince(timeline.date)
                let isOvertime = remaining < 0

                VStack(spacing: 2) {
                    Text(formatTime(remaining))
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .foregroundStyle(isOvertime ? .red : .white)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)

                    Text(isOvertime
                         ? String(localized: "OVERTIME")
                         : String(localized: "Remaining"))
                        .font(.caption2)
                        .foregroundStyle(isOvertime ? .red : .secondary)
                }
            }
        }
    }

    // MARK: - Section 2: Next Block

    private func nextBlockSection(_ context: WatchContext) -> some View {
        VStack(spacing: 2) {
            Text(String(localized: "Up Next"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if let nextTitle = context.nextBlockTitle {
                Text(nextTitle)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                if let nextStart = context.nextBlockStartTime {
                    Text(nextStart, format: .dateTime.hour().minute())
                        .font(.system(size: 20, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(String(localized: "Last block of the day"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Section 3: Sunset

    private func sunsetSection(_ sunset: Date) -> some View {
        VStack(spacing: 2) {
            Image(systemName: "sun.horizon.fill")
                .font(.caption)
                .foregroundStyle(.orange)

            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let remaining = sunset.timeIntervalSince(timeline.date)
                if remaining > 0 {
                    Text(formatTime(remaining))
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.orange)
                } else {
                    Text(String(localized: "Past sunset"))
                        .font(.caption)
                        .foregroundStyle(.orange.opacity(0.6))
                }
            }

            Text(sunset, format: .dateTime.hour().minute())
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Idle

    private var idleView: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(String(localized: "No Live Event"))
                .font(.headline)
            Text(String(localized: "Go live on your iPhone to start"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // MARK: - Helpers

    /// Formats a `TimeInterval` as mm:ss (or h:mm:ss for durations >= 1 hour).
    private func formatTime(_ seconds: TimeInterval) -> String {
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

#Preview {
    ContentView()
        .environment(WatchSessionManager())
}
