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
            // Lock Screen & Banner UI
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.attributes.eventName)
                        .font(.headline)
                    Text("Current: \(context.state.currentBlockName)")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }
                Spacer()
                Image(systemName: "calendar.badge.clock")
                    .font(.title2)
                    .foregroundStyle(.blue)
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading, priority: 0.5) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("SHIFT", systemImage: "calendar.badge.clock")
                            .font(.caption2.bold())
                            .foregroundStyle(.blue)
                        Text(context.attributes.eventName)
                            .font(.caption2)
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                    }
                    .frame(minHeight: 36)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Live")
                        .font(.caption2.bold())
                        .foregroundStyle(.green)
                        .frame(minHeight: 36)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Image(systemName: "clock.fill")
                            .foregroundStyle(.blue)
                        Text(context.state.currentBlockName)
                            .font(.footnote.bold())
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
                }
            } compactLeading: {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.blue)
            } compactTrailing: {
                Text("00:00")
                    .font(.caption2)
            } minimal: {
                Image(systemName: "clock")
                    .foregroundStyle(.blue)
            }
        }
    }
}
