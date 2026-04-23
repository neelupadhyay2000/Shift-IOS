//
//  EventExitLiveModeTransitionTests.swift
//  shiftTimelineTests
//
//  TDD for decoupling Live Mode UI state from persisted EventStatus.
//  The transition runs when the user exits the Live Dashboard:
//    - completed           → unchanged
//    - same calendar day   → remain .live
//    - different day       → revert to .planning (pre-event UI test)
//

import Foundation
import Models
import Testing

@Suite("EventModel.resolveStatusOnExitLiveMode")
struct EventExitLiveModeTransitionTests {

    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Toronto") ?? .current
        return cal
    }()

    private func makeEvent(status: EventStatus, date: Date) -> EventModel {
        EventModel(title: "Test", date: date, latitude: 0, longitude: 0, status: status)
    }

    @Test("Completed event is untouched")
    func completedEventIsUntouched() {
        let now = Date()
        let event = makeEvent(status: .completed, date: now)

        let resolved = event.resolveStatusOnExitLiveMode(now: now, calendar: calendar)

        #expect(resolved == .completed)
    }

    @Test("Completed event is untouched even on a different day")
    func completedEventIsUntouchedDifferentDay() {
        let now = Date()
        let tenDaysAgo = calendar.date(byAdding: .day, value: -10, to: now) ?? now
        let event = makeEvent(status: .completed, date: tenDaysAgo)

        let resolved = event.resolveStatusOnExitLiveMode(now: now, calendar: calendar)

        #expect(resolved == .completed)
    }

    @Test("Same calendar day → remain .live")
    func sameDayRemainsLive() {
        let now = Date()
        // Event date earlier the same day.
        let sameDayEarlier = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: now) ?? now
        let event = makeEvent(status: .live, date: sameDayEarlier)

        let resolved = event.resolveStatusOnExitLiveMode(now: now, calendar: calendar)

        #expect(resolved == .live)
    }

    @Test("Event scheduled tomorrow → revert to .planning")
    func futureDayRevertsToPlanning() {
        let now = Date()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let event = makeEvent(status: .live, date: tomorrow)

        let resolved = event.resolveStatusOnExitLiveMode(now: now, calendar: calendar)

        #expect(resolved == .planning)
    }

    @Test("Event scheduled yesterday → revert to .planning")
    func pastDayRevertsToPlanning() {
        let now = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let event = makeEvent(status: .live, date: yesterday)

        let resolved = event.resolveStatusOnExitLiveMode(now: now, calendar: calendar)

        #expect(resolved == .planning)
    }

    @Test("Planning status is returned unchanged — this helper only demotes .live")
    func planningStatusReturnedUnchanged() {
        // The transition helper is a one-way demoter: .live → .planning
        // when the calendar day no longer matches. It must never promote
        // .planning → .live. Promotion is a deliberate user action handled
        // when entering Live Mode, not when exiting it.
        let now = Date()
        let event = makeEvent(status: .planning, date: now)

        let resolved = event.resolveStatusOnExitLiveMode(now: now, calendar: calendar)

        #expect(resolved == .planning)
    }

    @Test("Midnight boundary — event 1 second after midnight same day remains .live")
    func midnightBoundarySameDay() {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 15
        components.hour = 0
        components.minute = 0
        components.second = 1
        guard let eventDate = calendar.date(from: components) else {
            Issue.record("Failed to build event date")
            return
        }
        components.hour = 23
        components.minute = 59
        components.second = 59
        guard let now = calendar.date(from: components) else {
            Issue.record("Failed to build now")
            return
        }
        let event = makeEvent(status: .live, date: eventDate)

        let resolved = event.resolveStatusOnExitLiveMode(now: now, calendar: calendar)

        #expect(resolved == .live)
    }

    @Test("One-minute difference across midnight → reverts to .planning")
    func crossMidnightRevertsToPlanning() {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 15
        components.hour = 23
        components.minute = 59
        components.second = 59
        guard let eventDate = calendar.date(from: components) else {
            Issue.record("Failed to build event date")
            return
        }
        components.day = 16
        components.hour = 0
        components.minute = 0
        components.second = 30
        guard let now = calendar.date(from: components) else {
            Issue.record("Failed to build now")
            return
        }
        let event = makeEvent(status: .live, date: eventDate)

        let resolved = event.resolveStatusOnExitLiveMode(now: now, calendar: calendar)

        #expect(resolved == .planning)
    }
}
