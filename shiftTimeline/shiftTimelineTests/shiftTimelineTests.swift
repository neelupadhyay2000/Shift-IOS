//
//  shiftTimelineTests.swift
//  shiftTimelineTests
//
//  Created by Neel Upadhyay on 2026-04-07.
//

import Testing

struct shiftTimelineTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
        // Swift Testing Documentation
        // https://developer.apple.com/documentation/testing
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
