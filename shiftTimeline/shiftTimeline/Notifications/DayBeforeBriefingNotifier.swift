import Foundation
import Models
import Services
import SwiftData
import UserNotifications
import os

/// Schedules a local "event tomorrow" briefing the evening before an event:
/// *"Tomorrow: Patel Wedding. First block 10:00 AM. Sunset 7:42 PM."*
///
/// Local-only, modelled on `GoldenHourNotifier`: deterministic per-event
/// identifiers so re-scheduling replaces instead of stacking, a pure
/// fire-time function for tests, and the shared scheduling seam
/// (`VendorNotificationScheduling`). Scheduled after event create/edit and
/// re-stamped for all upcoming events on every foreground, so the briefing
/// picks up later sunset enrichment and block changes.
enum DayBeforeBriefingNotifier {

    private static let logger = Logger(
        subsystem: "com.shift.notifications",
        category: "DayBeforeBriefingNotifier"
    )

    /// Local hour (24h) the briefing fires the evening before the event.
    nonisolated static let fireHour = 18

    /// How far ahead `scheduleUpcoming` looks for events to brief.
    nonisolated static let schedulingHorizon: TimeInterval = 7 * 24 * 3600

    /// Deterministic identifier per event so re-scheduling replaces the pending
    /// briefing instead of stacking duplicates.
    nonisolated static func identifier(for eventID: UUID) -> String {
        "daybefore-\(eventID.uuidString)"
    }

    // MARK: - Pure fire-time decision

    /// 6 PM local time the day before the event's first block — or `nil` when
    /// that moment has already passed (event is today, tomorrow-evening-created,
    /// or in the past). Pure + synchronous so it's unit-testable.
    nonisolated static func fireDate(
        eventStart: Date,
        now: Date,
        calendar: Calendar = .current
    ) -> Date? {
        guard let dayBefore = calendar.date(
            byAdding: .day, value: -1, to: calendar.startOfDay(for: eventStart)
        ), let fire = calendar.date(
            bySettingHour: fireHour, minute: 0, second: 0, of: dayBefore
        ) else { return nil }
        return fire > now ? fire : nil
    }

    // MARK: - Body composition

    /// Briefing body: event title, first block time, and sunset when cached.
    nonisolated static func body(
        eventTitle: String,
        firstBlockStart: Date?,
        sunsetTime: Date?
    ) -> String {
        var parts = [String(localized: "Tomorrow: \(eventTitle).")]
        if let firstBlockStart {
            let time = firstBlockStart.formatted(date: .omitted, time: .shortened)
            parts.append(String(localized: "First block \(time)."))
        }
        if let sunsetTime {
            let time = sunsetTime.formatted(date: .omitted, time: .shortened)
            parts.append(String(localized: "Sunset \(time)."))
        }
        return parts.joined(separator: " ")
    }

    // MARK: - Schedule

    /// Schedules (or replaces) the briefing for one event. Call after event
    /// creation and after edits that can move the date.
    @MainActor
    static func schedule(for event: EventModel, now: Date = .now) async {
        let blocks = (event.tracks ?? []).flatMap { $0.blocks ?? [] }
        let firstBlockStart = blocks.map(\.scheduledStart).min()
        await schedule(
            eventID: event.id,
            eventTitle: event.title,
            eventStart: firstBlockStart ?? event.date,
            firstBlockStart: firstBlockStart,
            sunsetTime: event.sunsetTime,
            now: now,
            center: UNUserNotificationCenter.current()
        )
    }

    /// Re-stamps briefings for every planning-stage event inside the scheduling
    /// horizon. Idempotent (deterministic identifiers); call on app foreground.
    @MainActor
    static func scheduleUpcoming(context: ModelContext, now: Date = .now) async {
        let horizon = now.addingTimeInterval(schedulingHorizon)
        let descriptor = FetchDescriptor<EventModel>(
            predicate: #Predicate { $0.date > now && $0.date < horizon },
            sortBy: [SortDescriptor(\.date)]
        )
        let upcoming = (try? context.fetch(descriptor)) ?? []
        for event in upcoming where event.status == .planning {
            await schedule(for: event, now: now)
        }
    }

    /// Testable overload — injected scheduler + clock, primitives only.
    static func schedule(
        eventID: UUID,
        eventTitle: String,
        eventStart: Date,
        firstBlockStart: Date?,
        sunsetTime: Date?,
        now: Date,
        center: any VendorNotificationScheduling,
        calendar: Calendar = .current
    ) async {
        guard let fire = fireDate(eventStart: eventStart, now: now, calendar: calendar) else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Event Tomorrow")
        content.body = body(
            eventTitle: eventTitle,
            firstBlockStart: firstBlockStart,
            sunsetTime: sunsetTime
        )
        content.sound = .default
        // Shared event-id key so a tap deep-links to the event via the existing
        // RemoteShiftPushHandler tap path (same as GoldenHourNotifier).
        content.userInfo = [VendorShiftNotificationContent.eventIDKey: eventID.uuidString]

        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute], from: fire
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifier(for: eventID),
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            logger.info("Scheduled day-before briefing for \"\(eventTitle, privacy: .public)\"")
        } catch {
            logger.error("Failed to schedule day-before briefing: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Removes the pending briefing (call when an event is deleted).
    @MainActor
    static func cancel(for eventID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [identifier(for: eventID)]
        )
    }
}
