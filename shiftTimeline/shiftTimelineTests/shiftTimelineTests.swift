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

    @Test @MainActor func timeBlockModelPersistsInSwiftDataContainer() async throws {
        let container = try ModelContainer(
            for: EventModel.self, TimelineTrack.self, TimeBlockModel.self,
                 VendorModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        let event = EventModel(
            title: "Wedding",
            date: Date(),
            latitude: 40.7128,
            longitude: -74.0060
        )
        context.insert(event)

        let track = TimelineTrack(name: "Main", sortOrder: 0, event: event)
        context.insert(track)

        let startDate = Date()
        let block = TimeBlockModel(
            title: "Ceremony",
            scheduledStart: startDate,
            duration: 1800,
            minimumDuration: 900,
            isPinned: true,
            notes: "Outdoor garden ceremony",
            colorTag: "#FF5733",
            icon: "heart.fill",
            status: .upcoming
        )
        block.track = track
        context.insert(block)
        try context.save()

        let descriptor = FetchDescriptor<TimeBlockModel>()
        let fetched = try context.fetch(descriptor)

        #expect(fetched.count == 1)

        let result = try #require(fetched.first)
        #expect(result.title == "Ceremony")
        #expect(result.scheduledStart == startDate)
        #expect(result.originalStart == startDate)
        #expect(result.duration == 1800)
        #expect(result.minimumDuration == 900)
        #expect(result.isPinned == true)
        #expect(result.notes == "Outdoor garden ceremony")
        #expect(result.voiceMemoURL == nil)
        #expect(result.colorTag == "#FF5733")
        #expect(result.icon == "heart.fill")
        #expect(result.status == .upcoming)
        #expect(result.requiresReview == false)
        #expect(result.track === track)
    }

    // MARK: - VendorModel CRUD

    @Test @MainActor func vendorModelCreateAndRead() async throws {
        let container = try ModelContainer(
            for: EventModel.self, TimelineTrack.self, TimeBlockModel.self,
                 VendorModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        let event = EventModel(
            title: "Wedding",
            date: Date(),
            latitude: 40.7128,
            longitude: -74.0060
        )
        context.insert(event)

        let vendor = VendorModel(
            name: "Jane Smith",
            role: .photographer,
            phone: "555-0100",
            email: "jane@example.com",
            notificationThreshold: 600
        )
        vendor.event = event
        context.insert(vendor)
        try context.save()

        let descriptor = FetchDescriptor<VendorModel>()
        let fetched = try context.fetch(descriptor)

        #expect(fetched.count == 1)

        let result = try #require(fetched.first)
        #expect(result.name == "Jane Smith")
        #expect(result.role == .photographer)
        #expect(result.phone == "555-0100")
        #expect(result.email == "jane@example.com")
        #expect(result.notificationThreshold == 600)
        #expect(result.hasAcknowledgedLatestShift == false)
        #expect(result.event === event)
        #expect(event.vendors.contains(where: { $0.id == vendor.id }))
    }

    @Test @MainActor func vendorModelUpdate() async throws {
        let container = try ModelContainer(
            for: EventModel.self, TimelineTrack.self, TimeBlockModel.self,
                 VendorModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        let event = EventModel(
            title: "Gala",
            date: Date(),
            latitude: 34.0522,
            longitude: -118.2437
        )
        context.insert(event)

        let vendor = VendorModel(name: "DJ Mike", role: .dj)
        vendor.event = event
        context.insert(vendor)
        try context.save()

        vendor.name = "DJ Mike V2"
        vendor.role = .mc
        vendor.phone = "555-0200"
        vendor.email = "mike@example.com"
        vendor.notificationThreshold = 900
        vendor.hasAcknowledgedLatestShift = true
        try context.save()

        let descriptor = FetchDescriptor<VendorModel>()
        let fetched = try context.fetch(descriptor)
        let result = try #require(fetched.first)

        #expect(result.name == "DJ Mike V2")
        #expect(result.role == .mc)
        #expect(result.phone == "555-0200")
        #expect(result.email == "mike@example.com")
        #expect(result.notificationThreshold == 900)
        #expect(result.hasAcknowledgedLatestShift == true)
    }

    @Test @MainActor func vendorModelDelete() async throws {
        let container = try ModelContainer(
            for: EventModel.self, TimelineTrack.self, TimeBlockModel.self,
                 VendorModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        let event = EventModel(
            title: "Corporate Retreat",
            date: Date(),
            latitude: 37.7749,
            longitude: -122.4194
        )
        context.insert(event)

        let vendor = VendorModel(name: "Catering Co", role: .caterer)
        vendor.event = event
        context.insert(vendor)
        try context.save()

        let beforeDelete = try context.fetch(FetchDescriptor<VendorModel>())
        #expect(beforeDelete.count == 1)

        context.delete(vendor)
        try context.save()

        let afterDelete = try context.fetch(FetchDescriptor<VendorModel>())
        #expect(afterDelete.count == 0)
    }

}
