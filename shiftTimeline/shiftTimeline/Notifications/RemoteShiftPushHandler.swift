import Foundation
import Models
import Services
import SwiftData

/// A foreground shift notification rendered as an in-app banner instead of a
/// system notification. The app-root view observes the most recent
/// one on `DeepLinkRouter` and surfaces it as a transient top toast that
/// deep-links to its event on tap.
///
/// `id` is unique per presentation so SwiftUI animates a fresh banner even when
/// two consecutive pushes carry the same event.
struct InAppShiftBanner: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let body: String
    let eventID: UUID
}

/// Handles an incoming APNs shift push on the client.
///
/// The `shift-notify` Edge Function sends a **background**
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

    /// Payload keys — must match the Edge Function's body.
    /// `nonisolated` so the nonisolated `parse` can read them.
    private nonisolated static let eventVendorIDKey = "event_vendor_id"
    private nonisolated static let deltaKey = "pending_shift_delta"
    /// Marketplace service-request pushes (request_received / request_response)
    /// carry the request id here — must match the Edge Function's REQUEST_ID_KEY (E11).
    nonisolated static let requestIDKey = "com.shift.requestID"

    /// Returns the service-request id when `userInfo` is a marketplace request push,
    /// else nil. `nonisolated` so the notification-tap delegate can extract it
    /// before hopping to the MainActor router.
    nonisolated static func parseRequestID(_ userInfo: [AnyHashable: Any]) -> UUID? {
        (userInfo[requestIDKey] as? String).flatMap { UUID(uuidString: $0) }
    }

    /// Routes a tapped service-request push to the Marketplace tab via the router.
    @MainActor
    static func routeRequestTap(_ requestID: UUID, router: DeepLinkRouter) {
        router.pendingDestination = .serviceRequest(id: requestID)
    }

    /// Returns a parsed payload when `userInfo` is one of our shift pushes, else nil.
    /// `nonisolated` so the (nonisolated) notification-tap delegate can extract the
    /// Sendable payload before hopping to the MainActor router.
    nonisolated static func parse(_ userInfo: [AnyHashable: Any]) -> ShiftPushPayload? {
        guard let raw = userInfo[VendorShiftNotificationContent.eventIDKey] as? String,
              let eventID = UUID(uuidString: raw) else { return nil }
        let eventVendorID = (userInfo[eventVendorIDKey] as? String).flatMap { UUID(uuidString: $0) }
        let delta = (userInfo[deltaKey] as? TimeInterval)
            ?? (userInfo[deltaKey] as? NSNumber)?.doubleValue
        return ShiftPushPayload(eventID: eventID, eventVendorID: eventVendorID, delta: delta)
    }

    /// Builds the in-app banner for a foreground shift notification.
    ///
    /// `AppDelegate`'s `willPresent` suppresses the system banner for any
    /// `shift-`prefixed notification while the app is visible; this turns the
    /// suppressed notification's already-formatted title/body + event id into the
    /// banner model the root view shows in its place. Returns nil for any
    /// notification that isn't one of our shift pushes (so non-shift foreground
    /// notifications fall through to the system presentation unchanged).
    /// `nonisolated` so it can run on the delegate's actor before hopping to the
    /// MainActor router; takes primitives so it's testable without `UNNotification`.
    nonisolated static func makeForegroundBanner(
        identifier: String,
        title: String,
        body: String,
        userInfo: [AnyHashable: Any]
    ) -> InAppShiftBanner? {
        guard identifier.hasPrefix("shift-"),
              let raw = userInfo[VendorShiftNotificationContent.eventIDKey] as? String,
              let eventID = UUID(uuidString: raw) else { return nil }
        return InAppShiftBanner(id: UUID(), title: title, body: body, eventID: eventID)
    }

    /// Routes a tapped shift notification to its event via `DeepLinkRouter`
    ///. `RootNavigator` observes `pendingDestination` and pushes
    /// `EventDetailView` for the event. Returns the routed event id.
    @MainActor
    @discardableResult
    static func routeTap(_ payload: ShiftPushPayload, router: DeepLinkRouter) -> UUID {
        router.pendingEventID = payload.eventID
        return payload.eventID
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
