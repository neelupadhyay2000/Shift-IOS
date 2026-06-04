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
/// is set on their `VendorModel`.
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
    static func processAndNotify(event: EventModel) async {
        await processAndNotify(
            event: event,
            center: UNUserNotificationCenter.current(),
            globalThresholdSeconds: readGlobalThresholdSeconds()
        )
    }

    /// Testable overload — accepts injected `NotificationScheduling`,
    /// global threshold, and dedupe store so tests never touch
    /// `UNUserNotificationCenter.current()` or `UserDefaults.standard`.
    static func processAndNotify(
        event: EventModel,
        center: any VendorNotificationScheduling,
        globalThresholdSeconds: TimeInterval,
        dedupeStore: UserDefaults = .standard
    ) async {
        let vendors = event.vendors ?? []
        let candidateVendors = vendors

        for vendor in candidateVendors {
            guard let delta = vendor.pendingShiftDelta else { continue }
            // Only post a visible push for shifts that exceed BOTH the per-vendor
            // threshold AND the planner's global Settings threshold ("Notify me
            // when shift exceeds..."). Smaller shifts still sync silently and
            // surface in the in-app banner via `pendingShiftDelta`.
            let willPost = Self.shouldPostVisibleNotification(
                delta: delta,
                vendorThresholdSeconds: vendor.notificationThreshold,
                globalThresholdSeconds: globalThresholdSeconds
            )
            SyncDiagnosticsCenter.shared.record(
                .notify,
                "evaluated",
                params: [
                    "deltaMin": "\(Int(delta / 60))",
                    "vendorThresholdMin": "\(Int(vendor.notificationThreshold / 60))",
                    "globalThresholdMin": "\(Int(globalThresholdSeconds / 60))",
                    "willPost": "\(willPost)",
                ]
            )
            guard willPost else { continue }

            // Dedupe: this scan runs on every app-active / 30s poll, but the
            // notification ID is deterministic, so re-adding would re-alert the
            // vendor for the same shift. Skip if we've already posted this exact
            // delta. We do NOT clear `pendingShiftDelta` — the in-app
            // acknowledgment banner reads it (and foreground pushes are suppressed).
            guard !alreadyPosted(delta: delta, vendorID: vendor.id, store: dedupeStore) else { continue }

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
                markPosted(delta: delta, vendorID: vendor.id, store: dedupeStore)
                logger.info("Posted shift notification for vendor \(vendor.name)")
                SyncDiagnosticsCenter.shared.record(.notify, "posted", params: ["deltaMin": "\(Int(delta / 60))"])
            } catch {
                logger.error("Failed to post notification for \(vendor.name): \(error.localizedDescription)")
                SyncDiagnosticsCenter.shared.record(
                    .notify,
                    "postFailed",
                    params: ["error": error.localizedDescription],
                    severity: .error
                )
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

    // MARK: - Post dedupe

    /// Device-local key for the last shift delta we posted a notification for,
    /// per vendor. Prevents re-alerting on every app-active/poll while the same
    /// shift is pending. Cleared implicitly when a new (different) delta arrives.
    private static func postedKey(_ vendorID: UUID) -> String {
        "shift-posted-delta-\(vendorID.uuidString)"
    }

    /// `true` when a notification for this exact delta was already posted to this vendor.
    static func alreadyPosted(delta: TimeInterval, vendorID: UUID, store: UserDefaults = .standard) -> Bool {
        let key = postedKey(vendorID)
        guard store.object(forKey: key) != nil else { return false }
        let stored = store.double(forKey: key)
        return abs(stored - delta) < 1  // within a second = same shift
    }

    private static func markPosted(delta: TimeInterval, vendorID: UUID, store: UserDefaults = .standard) {
        store.set(delta, forKey: postedKey(vendorID))
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
