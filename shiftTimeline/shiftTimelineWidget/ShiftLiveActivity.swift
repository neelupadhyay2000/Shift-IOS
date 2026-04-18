//
//  ShiftLiveActivity.swift
//  shiftTimelineWidgetExtension
//
//  Created by Neel Upadhyay on 2026-04-07.
//

import WidgetKit
import SwiftUI
import ActivityKit
import Foundation

// ShiftActivityAttributes is compiled directly by both the main app and
// widget extension targets (see ShiftActivityAttributes.swift), ensuring
// type identity across processes on real devices.

// The Widget UI Configuration
struct ShiftLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShiftActivityAttributes.self) { context in
            // Lock Screen & StandBy UI
            VStack(spacing: 0) {
                HStack(alignment: .center) {
                    // Leading — current block title
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.eventTitle)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Text(context.state.currentBlockTitle)
                            .font(.headline)
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                    }

                    Spacer()

                    // Trailing — live countdown timer (system-managed)
                    Text(context.state.endTime, style: .timer)
                        .font(.title.weight(.bold).monospacedDigit())
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.trailing)
                }

                // Bottom — next block subtitle
                HStack {
                    if let next = context.state.nextBlockTitle {
                        Label {
                            Text("Next: \(next)")
                                .font(.subheadline)
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                        } icon: {
                            Image(systemName: "forward.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Last block of the day")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    // Sunset pill
                    if let sunset = context.state.sunsetTime {
                        Label {
                            Text(sunset, style: .timer)
                                .font(.caption.monospacedDigit())
                        } icon: {
                            Image(systemName: "sunset.fill")
                                .font(.caption2)
                        }
                        .foregroundStyle(.yellow)
                    }
                }
                .padding(.top, 8)
            }
            .padding()
            .activityBackgroundTint(.black.opacity(0.75))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded — top: event title
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.eventTitle)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Label("Live", systemImage: "circle.fill")
                        .font(.caption2.bold())
                        .foregroundStyle(.green)
                }
                // Expanded — center: current block + countdown
                DynamicIslandExpandedRegion(.center) {
                    HStack {
                        Text(context.state.currentBlockTitle)
                            .font(.headline)
                            .lineLimit(1)
                        Spacer()
                        Text(context.state.endTime, style: .timer)
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.orange)
                    }
                }
                // Expanded — bottom: next block + sunset
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if let next = context.state.nextBlockTitle {
                            Label {
                                Text("Next: \(next)")
                                    .lineLimit(1)
                            } icon: {
                                Image(systemName: "forward.fill")
                                    .font(.caption2)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        } else {
                            Text("Last block")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let sunset = context.state.sunsetTime {
                            Label {
                                Text(sunset, style: .timer)
                                    .monospacedDigit()
                            } icon: {
                                Image(systemName: "sunset.fill")
                            }
                            .font(.caption)
                            .foregroundStyle(.yellow)
                        }
                    }
                    .padding(.top, 2)
                }
            } compactLeading: {
                // Compact pill — block title
                Text(context.state.currentBlockTitle)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } compactTrailing: {
                // Compact pill — live countdown
                Text(context.state.endTime, style: .timer)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.orange)
            } minimal: {
                // Minimal dot indicator
                Image(systemName: "timer")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }
}
