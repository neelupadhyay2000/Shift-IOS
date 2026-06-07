import Foundation
import Services
import Testing
import UserNotifications
@testable import shiftTimeline

// MARK: - Mock

/// Records every `UNNotificationRequest` passed to `add(_:)`.
private actor MockGoldenHourCenter: VendorNotificationScheduling {
    private(set) var addedRequests: [UNNotificationRequest] = []

    nonisolated func add(_ request: UNNotificationRequest) async throws {
        await record(request)
    }

    private func record(_ request: UNNotificationRequest) {
        addedRequests.append(request)
    }
}

/// SHIFT-649: a local golden-hour/sunset reminder scheduled at go-live.
@Suite("Golden-hour notification scheduling (SHIFT-649)")
struct GoldenHourNotifierTests {

    // MARK: - fireDate (pure)

    @Test("fire date is the lead time before golden hour when golden hour is known")
    func fireDatePrefersGoldenHour() throws {
        let now = Date()
        let golden = now.addingTimeInterval(2 * 3600)   // +2h
        let sunset = now.addingTimeInterval(3 * 3600)    // +3h
        let fire = try #require(GoldenHourNotifier.fireDate(
            goldenHourStart: golden, sunsetTime: sunset, now: now, leadTime: 30 * 60
        ))
        #expect(abs(fire.timeIntervalSince(golden.addingTimeInterval(-30 * 60))) < 1)
    }

    @Test("fire date falls back to sunset when golden hour is unknown")
    func fireDateFallsBackToSunset() throws {
        let now = Date()
        let sunset = now.addingTimeInterval(3 * 3600)
        let fire = try #require(GoldenHourNotifier.fireDate(
            goldenHourStart: nil, sunsetTime: sunset, now: now, leadTime: 30 * 60
        ))
        #expect(abs(fire.timeIntervalSince(sunset.addingTimeInterval(-30 * 60))) < 1)
    }

    @Test("fire date is nil when neither golden hour nor sunset is set")
    func fireDateNilWhenNoAnchor() {
        #expect(GoldenHourNotifier.fireDate(
            goldenHourStart: nil, sunsetTime: nil, now: Date()
        ) == nil)
    }

    @Test("fire date is nil when the lead time has already elapsed")
    func fireDateNilWhenPast() {
        let now = Date()
        // Golden hour only 10 min away — the 30-min lead is already in the past.
        let golden = now.addingTimeInterval(10 * 60)
        #expect(GoldenHourNotifier.fireDate(
            goldenHourStart: golden, sunsetTime: nil, now: now, leadTime: 30 * 60
        ) == nil)
    }

    // MARK: - schedule

    @Test("scheduling a future golden hour adds a calendar-triggered notification")
    func schedulesCalendarNotification() async throws {
        let now = Date()
        let golden = now.addingTimeInterval(2 * 3600)
        let eventID = UUID()
        let center = MockGoldenHourCenter()

        await GoldenHourNotifier.schedule(
            eventID: eventID, eventTitle: "Beach Wedding",
            goldenHourStart: golden, sunsetTime: now.addingTimeInterval(3 * 3600),
            now: now, center: center
        )

        let requests = await center.addedRequests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.identifier == "goldenhour-\(eventID.uuidString)")

        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        #expect(!trigger.repeats)
        let next = try #require(trigger.nextTriggerDate())
        // Seconds are dropped by the calendar trigger, so allow a one-minute window.
        #expect(abs(next.timeIntervalSince(golden.addingTimeInterval(-30 * 60))) < 60)

        // Deep-links to the event on tap via the shared event-id key.
        let routedEventID = request.content.userInfo[VendorShiftNotificationContent.eventIDKey] as? String
        #expect(routedEventID == eventID.uuidString)
    }

    @Test("scheduling does nothing when golden hour has effectively passed")
    func schedulesNothingWhenPast() async throws {
        let now = Date()
        let golden = now.addingTimeInterval(5 * 60) // within the lead window
        let center = MockGoldenHourCenter()

        await GoldenHourNotifier.schedule(
            eventID: UUID(), eventTitle: "Sunset Shoot",
            goldenHourStart: golden, sunsetTime: nil,
            now: now, center: center
        )

        #expect(await center.addedRequests.isEmpty)
    }
}
