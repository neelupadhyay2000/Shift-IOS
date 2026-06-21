import Foundation
import Models
import Services
import SwiftData
import UserNotifications
import os

/// Schedules a single local reminder that fires ~30 minutes before an event's
/// golden hour / sunset, hooked to go-live.
///
/// Local-only — no server involvement. Anchored on the cached
/// `EventModel.goldenHourStart` (the onset of the prime shooting window), falling
/// back to `EventModel.sunsetTime` when golden hour isn't known. Uses a
/// `UNCalendarNotificationTrigger` so the reminder survives app suspension/relaunch
/// and fires at the right wall-clock minute even if the app is never reopened.
///
/// Body formatting and the scheduling seam mirror `VendorShiftLocalNotifier` so
/// both local-notification paths behave consistently and stay testable.
enum GoldenHourNotifier {

    private static let logger = Logger(
        subsystem: "com.shift.notifications",
        category: "GoldenHourNotifier"
    )

    /// How far ahead of golden hour / sunset the reminder fires.
    static let leadTime: TimeInterval = 30 * 60

    /// How far ahead `scheduleUpcoming` looks for events to arm.
    nonisolated static let schedulingHorizon: TimeInterval = 7 * 24 * 3600

    /// Deterministic identifier per event so re-going-live replaces the pending
    /// reminder instead of stacking duplicates.
    static func identifier(for eventID: UUID) -> String {
        "goldenhour-\(eventID.uuidString)"
    }

    // MARK: - Pure fire-time decision

    /// The moment the reminder should fire: `leadTime` before the golden-hour
    /// onset (preferred) or sunset. Returns nil when neither is known or the lead
    /// time has already elapsed relative to `now` (nothing useful to schedule).
    /// Pure + synchronous so it can be unit-tested without `UNUserNotificationCenter`.
    static func fireDate(
        goldenHourStart: Date?,
        sunsetTime: Date?,
        now: Date,
        leadTime: TimeInterval = leadTime
    ) -> Date? {
        guard let anchor = goldenHourStart ?? sunsetTime else { return nil }
        let fire = anchor.addingTimeInterval(-leadTime)
        return fire > now ? fire : nil
    }

    // MARK: - Schedule

    /// Re-arms golden-hour reminders for every upcoming planning-stage event,
    /// fetching sunset enrichment first so the anchor (`goldenHourStart` /
    /// `sunsetTime`) exists. Cache-first, so it only hits the network for events
    /// missing sun times. Idempotent — deterministic identifiers replace pending
    /// requests — so it's safe to call on every foreground.
    ///
    /// This is what makes the reminder fire for *planned* events: previously it
    /// was only armed at go-live, so it never scheduled unless the user went
    /// live before the 30-minute lead window.
    @MainActor
    static func scheduleUpcoming(context: ModelContext, now: Date = .now) async {
        let horizon = now.addingTimeInterval(schedulingHorizon)
        let descriptor = FetchDescriptor<EventModel>(
            predicate: #Predicate { $0.date > now && $0.date < horizon },
            sortBy: [SortDescriptor(\.date)]
        )
        let upcoming = ((try? context.fetch(descriptor)) ?? [])
            .filter { $0.status == .planning }
        let sunsetService = SunsetService()
        for event in upcoming {
            _ = await sunsetService.fetchIfNeeded(for: event)
            // A concurrent purge (e.g. account switch) can delete the event at
            // the await above — reading a detached model faults fatally.
            guard !event.isDeleted, event.modelContext != nil else { continue }
            await schedule(for: event, now: now)
        }
        try? context.save()
    }

    /// Production entry — reads the cached values off the event and schedules
    /// against the real notification center. Call from go-live and after
    /// create/edit.
    @MainActor
    static func schedule(for event: EventModel, now: Date = .now) async {
        await schedule(
            eventID: event.id,
            eventTitle: event.title,
            goldenHourStart: event.goldenHourStart,
            sunsetTime: event.sunsetTime,
            now: now,
            center: UNUserNotificationCenter.current()
        )
    }

    /// Testable overload — injected scheduler + clock + calendar, primitives only
    /// so nothing non-Sendable crosses an isolation boundary.
    static func schedule(
        eventID: UUID,
        eventTitle: String,
        goldenHourStart: Date?,
        sunsetTime: Date?,
        now: Date,
        center: any VendorNotificationScheduling,
        calendar: Calendar = .current
    ) async {
        guard let fire = fireDate(
            goldenHourStart: goldenHourStart, sunsetTime: sunsetTime, now: now
        ) else { return }

        let usingGoldenHour = goldenHourStart != nil
        let leadMinutes = Int(leadTime / 60)

        let content = UNMutableNotificationContent()
        content.title = usingGoldenHour
            ? String(localized: "Golden Hour Soon")
            : String(localized: "Sunset Soon")
        content.body = usingGoldenHour
            ? String(localized: "Golden hour at \(eventTitle) starts in about \(leadMinutes) minutes — get into position.",
                     comment: "Golden-hour reminder body; first arg is the event title, second is minutes of lead time")
            : String(localized: "Sunset at \(eventTitle) is in about \(leadMinutes) minutes — get into position.",
                     comment: "Sunset reminder body; first arg is the event title, second is minutes of lead time")
        content.sound = .default
        // Reuse the shared event-id key so a tap deep-links to the event via the
        // existing RemoteShiftPushHandler tap path.
        content.userInfo = [VendorShiftNotificationContent.eventIDKey: eventID.uuidString]

        // Minute-granularity calendar trigger (seconds are intentionally dropped).
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
            logger.info("Scheduled golden-hour reminder for \"\(eventTitle, privacy: .public)\"")
            SyncDiagnosticsCenter.shared.record(
                .notify, "goldenHourScheduled",
                params: ["usingGoldenHour": "\(usingGoldenHour)"]
            )
        } catch {
            logger.error("Failed to schedule golden-hour reminder: \(error.localizedDescription, privacy: .public)")
            SyncDiagnosticsCenter.shared.record(
                .notify, "goldenHourScheduleFailed",
                params: ["error": error.localizedDescription],
                severity: .error
            )
        }
    }
}
