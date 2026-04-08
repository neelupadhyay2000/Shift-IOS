//
//  shiftTimelineTests.swift
//  shiftTimelineTests
//
//  Created by Neel Upadhyay on 2026-04-07.
//

import Foundation
import Models
import SwiftData
import Testing

struct shiftTimelineTests {

    @Test func eventModelCanBeInstantiated() async throws {
        let event = EventModel(
            title: "Test Event",
            date: Date(),
            latitude: 40.7128,
            longitude: -74.0060
        )

        #expect(event.title == "Test Event")
        #expect(event.latitude == 40.7128)
        #expect(event.longitude == -74.0060)
        #expect(event.status == .planning)
        #expect(event.venueNames.isEmpty)
        #expect(event.sunsetTime == nil)
        #expect(event.goldenHourStart == nil)
        #expect(event.tracks.isEmpty)
    }

    @Test func timelineTrackCanBeInstantiated() async throws {
        let event = EventModel(
            title: "Test Event",
            date: Date(),
            latitude: 0,
            longitude: 0
        )

        let track = TimelineTrack(
            name: "Main",
            sortOrder: 0,
            event: event
        )

        #expect(track.name == "Main")
        #expect(track.sortOrder == 0)
        #expect(track.event === event)
        #expect(track.blocks.isEmpty)
    }

}
