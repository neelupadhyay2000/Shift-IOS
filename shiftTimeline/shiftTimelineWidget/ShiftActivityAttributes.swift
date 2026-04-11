//
//  ShiftActivityAttributes.swift
//  shiftTimeline
//
//  Shared between the main app target and the widget extension target.
//  Both targets compile this file directly so the ActivityAttributes type
//  is identical across processes — required for Live Activities on real
//  devices and TestFlight.
//

import ActivityKit
import Foundation

public struct ShiftActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Dynamic data that updates (e.g., current block name)
        public var currentBlockName: String

        public init(currentBlockName: String) {
            self.currentBlockName = currentBlockName
        }
    }

    /// Static data that doesn't change for the lifetime of the activity
    public var eventName: String

    public init(eventName: String) {
        self.eventName = eventName
    }
}
