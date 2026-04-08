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
import Models

// 1. The Data Model
struct ShiftActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic data that updates (e.g., time remaining)
        var currentBlockName: String
    }
    // Static data that doesn't change (e.g., Event Name)
    var eventName: String
}

// 2. The Widget UI Configuration
struct ShiftLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShiftActivityAttributes.self) { context in
            // Lock Screen & Banner UI
            VStack {
                Text(context.attributes.eventName)
                    .font(.headline)
                Text("Current: \(context.state.currentBlockName)")
                    .font(.subheadline)
                    .foregroundColor(.blue)
            }
            .padding()
        } dynamicIsland: { context in
            // Dynamic Island configuration (Required for Live Activities)
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Text("SHIFT") }
                DynamicIslandExpandedRegion(.trailing) { Text("Live") }
                DynamicIslandExpandedRegion(.bottom) { Text(context.state.currentBlockName) }
            } compactLeading: {
                Text("S")
            } compactTrailing: {
                Text("Live")
            } minimal: {
                Text("S")
            }
        }
    }
}
