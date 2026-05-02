import Foundation
import UserNotifications
import Models
import Services
import os

// MARK: - Notification scheduling seam

/// Abstraction over `UNUserNotificationCenter` so `VendorShiftLocalNotifier`
/// can be tested without the real notification center.
///
/// Production code passes `UNUserNotificationCenter.current()`. Tests pass a
/// `MockNotificationCenter` that records calls and returns canned answers.
protocol VendorNotificationScheduling: Sendable {
    func add(_ request: UNNotificationRequest) async throws
}

extension UNUserNotificationCenter: VendorNotificationScheduling {}

/// Posts visible local notifications to vendors when `pendingShiftDelta`
/// is set on their `VendorModel` after a CloudKit sync.
///
/// Body formatting is delegated to `VendorShiftNotificationContent` (in
/// SHIFTKit) so it can be unit-tested independently.
enum VendorShiftLocalNotifier {

    private static let logger = Logger(
        subsystem: "com.shift.notifications",
        category: "VendorShiftLocalNotifier"
    )

    /// Default global threshold (minutes) when the user has never adjusted the Settings slider.
    /// Mirrors the `@AppStorage` default declared in `SettingsView`.
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

    /// Scans vendors on the given event for a non-nil `pendingShiftDelta`
    /// that exceeds **both** their per-vendor threshold and the planner's
    /// global Settings threshold. Posts a visible local notification only for
    /// above-threshold vendors.
    ///
    /// `currentUserRecordName` scopes the scan to the matching vendor entry so
    /// a vendor device only receives a notification for itself, not for all
    /// vendors in the shared event. Pass `nil` to process all vendors (legacy
    /// path / tests).
    static func processAndNotify(event: EventModel, currentUserRecordName: String? = nil) async {
        await processAndNotify(
            event: event,
            center: UNUserNotificationCenter.current(),
            globalThresholdSeconds: readGlobalThresholdSeconds(),
            currentUserRecordName: currentUserRecordName
        )
    }

    /// Testable overload — accepts injected `NotificationScheduling`,
    /// global threshold, and optional identity so tests never touch
    /// `UNUserNotificationCenter.current()` or `UserDefaults.standard`.
    static func processAndNotify(
        event: EventModel,
        center: any VendorNotificationScheduling,
        globalThresholdSeconds: TimeInterval,
        currentUserRecordName: String? = nil
    ) async {
        let vendors = event.vendors ?? []

        // When the current user's record name is known, restrict processing
        // to only their own vendor entry. This prevents a vendor's device from
        // posting notifications on behalf of other vendors they can see in the
        // shared event. Falls back to all vendors when cloudKitRecordName is
        // not yet populated (e.g. legacy entries without the field set).
        let candidateVendors: [VendorModel]
        if let recordName = currentUserRecordName {
            let matched = vendors.filter { $0.cloudKitRecordName == recordName }
            candidateVendors = matched.isEmpty ? vendors : matched
        } else {
            candidateVendors = vendors
        }

        for vendor in candidateVendors {
            guard let delta = vendor.pendingShiftDelta else { continue }
            // Only post a visible push for shifts that exceed BOTH the per-vendor
            // threshold AND the planner's global Settings threshold ("Notify me
            // when shift exceeds..."). Smaller shifts still sync silently and
            // surface in the in-app banner via `pendingShiftDelta`.
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

            // Deterministic ID per vendor — replaces any prior shift
            // notification so we don't spam if processAndNotify runs again
            // before the vendor acknowledges.
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

            // pendingShiftDelta is intentionally preserved — the in-app
            // acknowledgment banner reads it to display the shift amount.
            // It is cleared when the vendor taps the banner to acknowledge.
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
