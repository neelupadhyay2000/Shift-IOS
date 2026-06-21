import Foundation
import Models
import Services
import UserNotifications
import os

/// Immediate, planning-time heads-up notices fired when a planner adds a block:
///
/// - **Rain** — WeatherKit forecasts precipitation ≥ ``rainThreshold`` during
///   the block's time/location.
/// - **Golden hour** — the block's window overlaps the golden-hour → sunset
///   window (great-light flag for photographers).
///
/// Distinct from ``GoldenHourNotifier`` (which fires 30 minutes before golden
/// hour on the event day): these are informational and delivered right after
/// the block is saved, so the planner can adjust. Deterministic per-block
/// identifiers mean editing a block replaces its earlier notice rather than
/// stacking duplicates.
enum BlockPlanningNotifier {

    private static let logger = Logger(
        subsystem: "com.shift.notifications",
        category: "BlockPlanningNotifier"
    )

    /// Rain probability (0–1) at or above which the rain notice fires. Matches
    /// the in-app banner threshold (`WeatherSnapshot.atRiskEntries`) so the two
    /// agree. Set to 30% because WeatherKit's hourly precipitation chance rarely
    /// exceeds ~45% even in heavy-rain regions.
    static let rainThreshold: Double = 0.3

    static func rainIdentifier(for blockID: UUID) -> String { "block-rain-\(blockID.uuidString)" }
    static func goldenHourIdentifier(for blockID: UUID) -> String { "block-golden-\(blockID.uuidString)" }

    // MARK: - Pure overlap test

    /// Whether the block window `[blockStart, blockEnd]` intersects the
    /// golden-hour window `[goldenHourStart, sunset]`. Pure + synchronous so it's
    /// unit-testable without `UNUserNotificationCenter`.
    static func overlapsGoldenHour(
        blockStart: Date,
        blockEnd: Date,
        goldenHourStart: Date,
        sunset: Date
    ) -> Bool {
        blockStart < sunset && blockEnd > goldenHourStart
    }

    // MARK: - Production entry

    /// Resolves the block + event into primitives (block venue coordinates,
    /// falling back to the event's), then checks rain and golden hour and posts
    /// notices. Call right after a new block is saved.
    @MainActor
    static func notifyForNewBlock(_ block: TimeBlockModel, in event: EventModel) async {
        let latitude = block.blockLatitude != 0 ? block.blockLatitude : event.latitude
        let longitude = block.blockLongitude != 0 ? block.blockLongitude : event.longitude
        await notify(
            blockID: block.id,
            blockTitle: block.title,
            blockStart: block.scheduledStart,
            blockDuration: block.duration,
            latitude: latitude,
            longitude: longitude,
            eventID: event.id,
            center: UNUserNotificationCenter.current()
        )
    }

    /// Testable core — primitives only and an injected scheduler, so nothing
    /// non-`Sendable` crosses an isolation boundary.
    static func notify(
        blockID: UUID,
        blockTitle: String,
        blockStart: Date,
        blockDuration: TimeInterval,
        latitude: Double,
        longitude: Double,
        eventID: UUID,
        center: any VendorNotificationScheduling
    ) async {
        // No coordinates → no forecast/sun data to evaluate.
        guard latitude != 0 || longitude != 0 else { return }
        let blockEnd = blockStart.addingTimeInterval(blockDuration)

        // Rain — a fresh single-block fetch so a stale event-level cache can't
        // mask the new block's forecast.
        if let snapshot = try? await WeatherService().fetch(
            blockTokens: [(id: blockID, scheduledStart: blockStart, latitude: latitude, longitude: longitude)]
        ),
           let entry = snapshot.entries.first(where: { $0.blockId == blockID }),
           entry.rainProbability >= rainThreshold {
            let percentage = Int((entry.rainProbability * 100).rounded())
            await post(
                identifier: rainIdentifier(for: blockID),
                title: String(localized: "Rain Expected"),
                body: String(
                    localized: "Rain is likely during \(blockTitle) (\(percentage)% chance). Consider an indoor backup.",
                    comment: "Planning rain notice; args: block title, percentage chance"
                ),
                eventID: eventID,
                center: center
            )
        }

        // Golden hour — does the block overlap the golden-hour → sunset window?
        if let sun = try? await SunsetService().fetch(
            latitude: latitude, longitude: longitude, date: blockStart
        ),
           overlapsGoldenHour(
               blockStart: blockStart, blockEnd: blockEnd,
               goldenHourStart: sun.goldenHourStart, sunset: sun.sunset
           ) {
            await post(
                identifier: goldenHourIdentifier(for: blockID),
                title: String(localized: "Golden Hour"),
                body: String(
                    localized: "\(blockTitle) falls during golden hour — ideal light for photos.",
                    comment: "Planning golden-hour notice; arg: block title"
                ),
                eventID: eventID,
                center: center
            )
        }
    }

    // MARK: - Post

    private static func post(
        identifier: String,
        title: String,
        body: String,
        eventID: UUID,
        center: any VendorNotificationScheduling
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // Shared event-id key so a tap deep-links to the event via the existing
        // RemoteShiftPushHandler tap path.
        content.userInfo = [VendorShiftNotificationContent.eventIDKey: eventID.uuidString]

        // `trigger: nil` delivers immediately. The id isn't a "shift-" id, so the
        // app's `willPresent` handler shows it as a banner even in the foreground.
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        do {
            try await center.add(request)
            logger.info("Posted planning notice \(identifier, privacy: .public)")
        } catch {
            logger.error("Failed to post planning notice: \(error.localizedDescription, privacy: .public)")
        }
    }
}
