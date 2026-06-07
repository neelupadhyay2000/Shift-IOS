import Foundation
import Models
import Services
import SwiftData

/// Handles an incoming APNs shift push on the client (SHIFT-646).
///
/// The `shift-notify` Edge Function (SHIFT-644) sends a **background**
/// (content-available) push so iOS wakes the app; this turns that wake into a
/// **rich local notification** by reusing `VendorShiftLocalNotifier` /
/// `VendorShiftNotificationContent` — the exact same formatter the in-app path
/// uses. The push only carries identifiers + the authoritative delta, so a
/// freshly-woken app (whose Realtime stream was suspended) still has a
/// `pendingShiftDelta` to render and to drive the in-app acknowledgment banner.
enum RemoteShiftPushHandler {

    /// Sendable projection of the push `userInfo`, parsed on the delegate's actor
    /// before any `Task` so the non-Sendable dictionary never crosses isolation.
    struct ShiftPushPayload: Sendable {
        let eventID: UUID
        let eventVendorID: UUID?
        let delta: TimeInterval?
    }

    /// Payload keys — must match the Edge Function's body (SHIFT-644).
    private static let eventVendorIDKey = "event_vendor_id"
    private static let deltaKey = "pending_shift_delta"

    /// Returns a parsed payload when `userInfo` is one of our shift pushes, else nil.
    static func parse(_ userInfo: [AnyHashable: Any]) -> ShiftPushPayload? {
        guard let raw = userInfo[VendorShiftNotificationContent.eventIDKey] as? String,
              let eventID = UUID(uuidString: raw) else { return nil }
        let eventVendorID = (userInfo[eventVendorIDKey] as? String).flatMap { UUID(uuidString: $0) }
        let delta = (userInfo[deltaKey] as? TimeInterval)
            ?? (userInfo[deltaKey] as? NSNumber)?.doubleValue
        return ShiftPushPayload(eventID: eventID, eventVendorID: eventVendorID, delta: delta)
    }

    /// Production entry: posts via the real notification center + Settings threshold.
    /// Creates its own `ModelContext` from the Sendable container so nothing
    /// non-Sendable crosses the `Task` boundary at the call site.
    @discardableResult
    static func handle(payload: ShiftPushPayload, container: ModelContainer) async -> Bool {
        guard let event = prepare(payload: payload, context: ModelContext(container)) else { return false }
        await VendorShiftLocalNotifier.processAndNotify(event: event)
        return true
    }

    /// Testable entry: injected scheduler, global threshold, and dedupe store.
    @discardableResult
    static func handle(
        payload: ShiftPushPayload,
        container: ModelContainer,
        center: any VendorNotificationScheduling,
        globalThresholdSeconds: TimeInterval,
        dedupeStore: UserDefaults = .standard
    ) async -> Bool {
        guard let event = prepare(payload: payload, context: ModelContext(container)) else { return false }
        await VendorShiftLocalNotifier.processAndNotify(
            event: event,
            center: center,
            globalThresholdSeconds: globalThresholdSeconds,
            dedupeStore: dedupeStore
        )
        return true
    }

    /// Resolves the event locally and stamps the payload's delta onto the targeted
    /// vendor so the notifier has a `pendingShiftDelta` to render. Returns nil when
    /// the event isn't on this device (nothing to notify about).
    private static func prepare(payload: ShiftPushPayload, context: ModelContext) -> EventModel? {
        let eventID = payload.eventID
        let descriptor = FetchDescriptor<EventModel>(predicate: #Predicate { $0.id == eventID })
        guard let event = try? context.fetch(descriptor).first else { return nil }

        if let delta = payload.delta,
           let eventVendorID = payload.eventVendorID,
           let vendor = (event.vendors ?? []).first(where: { $0.id == eventVendorID }) {
            vendor.pendingShiftDelta = delta
            vendor.hasAcknowledgedLatestShift = false
        }
        return event
    }
}
