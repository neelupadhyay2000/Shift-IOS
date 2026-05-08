import Foundation
import UserNotifications
import Models
import Services
import os

// MARK: - Notification scheduling seam

/// Abstraction over `UNUserNotificationCenter` for testability.
protocol VendorNotificationScheduling: Sendable {
    func add(_ request: UNNotificationRequest) async throws
}

extension UNUserNotificationCenter: VendorNotificationScheduling {}

/// Posts local notifications to vendors when `pendingShiftDelta` is set after a CloudKit sync.
enum VendorShiftLocalNotifier {

    private static let logger = Logger(
        subsystem: "com.shift.notifications",
        category: "VendorShiftLocalNotifier"
    )

    /// Default global threshold (minutes) matching the `SettingsView` `@AppStorage` default.
    private static let defaultGlobalThresholdMinutes: Double = 10

    // MARK: - Authorization

    /// Requests notification permission. Call once at launch.
    static func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            logger.info("Notification authorization \(granted ? "granted" : "denied")")
        } catch {
            logger.error("Failed to request notification authorization: \(error.localizedDescription)")
        }
    }

    // MARK: - Scan & Post

    /// Scans vendors for `pendingShiftDelta` exceeding per-vendor and global thresholds, posts local notifications.
    /// `currentUserRecordName` scopes the scan to the matching vendor entry; pass `nil` to process all (tests).
    static func processAndNotify(event: EventModel, currentUserRecordName: String? = nil) async {
        await processAndNotify(
            event: event,
            center: UNUserNotificationCenter.current(),
            globalThresholdSeconds: readGlobalThresholdSeconds(),
            currentUserRecordName: currentUserRecordName
        )
    }

    /// Testable overload with injected `NotificationScheduling`, global threshold, and identity.
    static func processAndNotify(
        event: EventModel,
        center: any VendorNotificationScheduling,
        globalThresholdSeconds: TimeInterval,
        currentUserRecordName: String? = nil
    ) async {
        let vendors = event.vendors ?? []

        // Restrict to the current user's own vendor entry when record name is known.
        // Falls back to all vendors for legacy entries without `cloudKitRecordName`.
        let candidateVendors: [VendorModel]
        if let recordName = currentUserRecordName {
            let matched = vendors.filter { $0.cloudKitRecordName == recordName }
            candidateVendors = matched.isEmpty ? vendors : matched
        } else {
            candidateVendors = vendors
        }

        for vendor in candidateVendors {
            guard let delta = vendor.pendingShiftDelta else { continue }
            // Require shift to exceed BOTH per-vendor and global thresholds.
            guard Self.shouldPostVisibleNotification(
                delta: delta,
                vendorThresholdSeconds: vendor.notificationThreshold,
                globalThresholdSeconds: globalThresholdSeconds
            ) else { continue }

            let body = VendorShiftNotificationContent.body(
                delta: delta,
                vendor: vendor
            )

            let content = UNMutableNotificationContent()
            content.title = String(localized: "Timeline Update")
            content.body = body
            content.sound = .default
            content.userInfo = [
                VendorShiftNotificationContent.eventIDKey: event.id.uuidString
            ]

            // Deterministic ID per vendor — replaces prior shift notification.
            let request = UNNotificationRequest(
                identifier: "shift-\(vendor.id.uuidString)",
                content: content,
                trigger: nil
            )

            do {
                try await center.add(request)
                logger.info("Posted shift notification for vendor \(vendor.name)")
            } catch {
                logger.error("Failed to post notification for \(vendor.name): \(error.localizedDescription)")
            }

            // pendingShiftDelta is preserved — cleared when vendor taps the in-app acknowledgment banner.
            vendor.hasAcknowledgedLatestShift = false
        }
    }

    // MARK: - Global threshold

    /// Pure decision point for whether a shift delta warrants a visible push, given the
    /// vendor's per-vendor threshold and the planner's global Settings threshold.
    /// Extracted from `processAndNotify` so it can be unit-tested without `UNUserNotificationCenter`.
    static func shouldPostVisibleNotification(
        delta: TimeInterval,
        vendorThresholdSeconds: TimeInterval,
        globalThresholdSeconds: TimeInterval
    ) -> Bool {
        let effectiveThreshold = max(vendorThresholdSeconds, globalThresholdSeconds)
        return abs(delta) >= effectiveThreshold
    }

    /// Reads the global "Notify me when shift exceeds…" preference from `UserDefaults`,
    /// returning seconds. Falls back to the `@AppStorage` default when the key is unset.
    private static func readGlobalThresholdSeconds() -> TimeInterval {
        let key = SettingsDefaultsKey.notificationThresholdMinutes
        let raw = UserDefaults.standard.object(forKey: key) as? Double
        let minutes = raw ?? defaultGlobalThresholdMinutes
        return minutes * 60
    }
}
