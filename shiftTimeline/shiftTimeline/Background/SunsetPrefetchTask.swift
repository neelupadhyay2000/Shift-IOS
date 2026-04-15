import BackgroundTasks
import SwiftData
import Models
import Services
import os

/// Registers and handles a `BGAppRefreshTask` that pre-fetches sunset and
/// golden hour data for events scheduled within the next 48 hours.
///
/// Results are cached in `EventModel.sunsetTime` / `.goldenHourStart` so the
/// data is available offline on event day.
enum SunsetPrefetchTask {

    static let identifier = "com.neelsoftwaresolutions.shiftTimeline.sunset-prefetch"

    private static let logger = Logger(
        subsystem: "com.neelsoftwaresolutions.shiftTimeline",
        category: "SunsetPrefetch"
    )

    // MARK: - Registration

    /// Call once at app launch (before the end of `application(_:didFinishLaunchingWithOptions:)`
    /// or in the `App` init) to register the task handler with `BGTaskScheduler`.
    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier,
            using: nil
        ) { task in
            guard let bgTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handleRefresh(bgTask)
        }
        logger.info("Registered BGAppRefreshTask: \(identifier)")
    }

    // MARK: - Scheduling

    /// Submits (or re-submits) a daily refresh request.
    /// Safe to call multiple times — BGTaskScheduler replaces existing requests
    /// with the same identifier.
    static func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        // Request earliest 6 hours from now to avoid excessive wake-ups.
        request.earliestBeginDate = Calendar.current.date(
            byAdding: .hour, value: 6, to: .now
        )

        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("Scheduled next sunset prefetch")
        } catch {
            logger.error("Failed to schedule sunset prefetch: \(error.localizedDescription)")
        }
    }

    // MARK: - Handler

    private static func handleRefresh(_ task: BGAppRefreshTask) {
        // Schedule the next run before starting work.
        scheduleNextRefresh()

        let workTask = Task {
            await prefetchSunsetData()
        }

        // If the system kills us, cancel the async work.
        task.expirationHandler = {
            workTask.cancel()
        }

        Task {
            _ = await workTask.result
            task.setTaskCompleted(success: !workTask.isCancelled)
        }
    }

    // MARK: - Prefetch Logic

    @MainActor
    private static func prefetchSunsetData() async {
        let container = PersistenceController.shared.container
        let context = container.mainContext

        let now = Date.now
        guard let cutoff = Calendar.current.date(byAdding: .hour, value: 48, to: now) else {
            return
        }

        let descriptor = FetchDescriptor<EventModel>(
            predicate: #Predicate<EventModel> {
                $0.date >= now && $0.date <= cutoff
            }
        )

        guard let events = try? context.fetch(descriptor) else {
            logger.info("No events fetched — no-op")
            return
        }

        let service = SunsetService()
        var fetchCount = 0

        for event in events {
            guard !Task.isCancelled else { break }

            // fetchIfNeeded is a no-op if already cached or no coordinates.
            if let _ = await service.fetchIfNeeded(for: event) {
                fetchCount += 1
            }
        }

        if fetchCount > 0 {
            try? context.save()
            logger.info("Pre-fetched sunset data for \(fetchCount) event(s)")
        } else {
            logger.info("No events needed sunset data refresh")
        }
    }
}
