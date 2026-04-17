import Foundation
import UserNotifications
import Models
import Services
import os

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

    /// Scans all vendors on the given event for a non-nil `pendingShiftDelta`.
    /// For each qualifying vendor, posts a personalised local notification
    /// and clears the pending delta.
    static func processAndNotify(event: EventModel) async {
        let vendors = event.vendors ?? []
        for vendor in vendors {
            guard let delta = vendor.pendingShiftDelta else { continue }

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

            let request = UNNotificationRequest(
                identifier: "shift-\(vendor.id.uuidString)-\(Date.now.timeIntervalSince1970)",
                content: content,
                trigger: nil
            )

            do {
                try await UNUserNotificationCenter.current().add(request)
                logger.info("Posted shift notification for vendor \(vendor.name)")
            } catch {
                logger.error("Failed to post notification for \(vendor.name): \(error.localizedDescription)")
            }

            vendor.pendingShiftDelta = nil
            vendor.hasAcknowledgedLatestShift = false
        }
    }
}
