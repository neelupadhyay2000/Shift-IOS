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
    public struct ContentState: Codable, Hashable, Sendable {
        /// Title of the currently active block (e.g. "Ceremony").
        public var currentBlockTitle: String
        /// Scheduled end time of the active block — drives the countdown timer.
        public var endTime: Date
        /// Title of the next upcoming block, if any.
        public var nextBlockTitle: String?
        /// Sunset time for the event day, if available.
        public var sunsetTime: Date?

        public init(
            currentBlockTitle: String,
            endTime: Date,
            nextBlockTitle: String? = nil,
            sunsetTime: Date? = nil
        ) {
            self.currentBlockTitle = currentBlockTitle
            self.endTime = endTime
            self.nextBlockTitle = nextBlockTitle
            self.sunsetTime = sunsetTime
        }
    }

    /// Event title — set once when the Live Activity starts, never changes.
    public var eventTitle: String

    public init(eventTitle: String) {
        self.eventTitle = eventTitle
    }
}
