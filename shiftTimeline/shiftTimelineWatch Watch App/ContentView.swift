//
//  ContentView.swift
//  shiftTimelineWatch Watch App
//
//  Created by Neel Upadhyay on 2026-04-07.
//

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

                // Active block countdown
                VStack(spacing: 4) {
                    Text(context.activeBlockTitle)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    TimelineView(.periodic(from: .now, by: 1)) { (timeline: TimelineViewDefaultContext) in
                        let remaining = context.activeBlockEndTime.timeIntervalSince(timeline.date)
                        Text(formatTime(remaining))
                            .font(.system(size: 36, design: .monospaced))
                            .foregroundColor(remaining > 0 ? .white : .red)
                    }
                }

                Divider()

                // Next block
                VStack(spacing: 2) {
                    Text(String(localized: "Next"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if let nextTitle = context.nextBlockTitle {
                        Text(nextTitle)
                            .font(.subheadline)
                            .lineLimit(1)

                        if let nextStart = context.nextBlockStartTime {
                            Text(nextStart, format: .dateTime.hour().minute())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(String(localized: "Last block of the day"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Sunset
                if let sunset = context.sunsetTime, sunset > .now {
                    Divider()
                    VStack(spacing: 2) {
                        Image(systemName: "sun.horizon")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text(sunset, style: .timer)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                // Queued indicator
                if sessionManager.isCommandQueued {
                    Text(String(localized: "Shift queued"))
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
            }
            .padding(.horizontal)
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
