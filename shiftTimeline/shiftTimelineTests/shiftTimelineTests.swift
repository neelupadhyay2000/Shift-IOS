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
import Foundation
import Models
import SwiftData

struct shiftTimelineTests {

    @Test func eventModelCanBeInstantiated() async throws {
        let event = EventModel(
            title: "Test Wedding",
            date: Date(),
            latitude: 40.7128,
            longitude: -74.0060,
            venueNames: ["Grand Ballroom"],
            status: .planning
        )

        #expect(event.title == "Test Wedding")
        #expect(event.latitude == 40.7128)
        #expect(event.longitude == -74.0060)
        #expect(event.venueNames == ["Grand Ballroom"])
        #expect(event.sunsetTime == nil)
        #expect(event.goldenHourStart == nil)
        #expect(event.status == .planning)
    }

}
