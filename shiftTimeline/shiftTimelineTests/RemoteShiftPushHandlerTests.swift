import Foundation
import Models
import Services
import SwiftData
import Testing
import UserNotifications
@testable import shiftTimeline

// MARK: - Mock

/// Records every `UNNotificationRequest` passed to `add(_:)`.
/// Actor-isolated so the off-main `processAndNotify` can call it safely.
private actor MockNotificationCenter: VendorNotificationScheduling {
    private(set) var addedRequests: [UNNotificationRequest] = []

    nonisolated func add(_ request: UNNotificationRequest) async throws {
        await record(request)
    }

    private func record(_ request: UNNotificationRequest) {
        addedRequests.append(request)
    }
}

@Suite("Remote shift push handling (SHIFT-646)")
struct RemoteShiftPushHandlerTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            EventModel.self, VendorModel.self, TimelineTrack.self,
            TimeBlockModel.self, ShiftRecord.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Seeds an event + a vendor with an upcoming assigned block, saved to the
    /// store so the handler's own context can fetch it. Returns the ids.
    @discardableResult
    private func seed(
        into context: ModelContext,
        vendorThreshold: TimeInterval = 600,
        blockTitle: String = "First Dance"
    ) throws -> (eventID: UUID, vendorID: UUID) {
        let event = EventModel(title: "Gala", date: .now, latitude: 0, longitude: 0)
        context.insert(event)

        let vendor = VendorModel(name: "Avery", role: .photographer, notificationThreshold: vendorThreshold)
        context.insert(vendor)
        vendor.event = event

        let block = TimeBlockModel(
            title: blockTitle,
            scheduledStart: .now.addingTimeInterval(3600),
            duration: 1800,
            isPinned: false
        )
        block.status = .upcoming
        context.insert(block)
        vendor.assignedBlocks = [block]

        try context.save()
        return (event.id, vendor.id)
    }

    @Test("a received shift push posts a rich local notification via the existing formatter")
    func postsRichLocalNotification() async throws {
        let container = try makeContainer()
        let ids = try seed(into: ModelContext(container))
        let center = MockNotificationCenter()
        let store = try #require(UserDefaults(suiteName: "test-push-\(UUID().uuidString)"))

        let payload = RemoteShiftPushHandler.ShiftPushPayload(
            eventID: ids.eventID, eventVendorID: ids.vendorID, delta: 900 // +15 min
        )

        let handled = await RemoteShiftPushHandler.handle(
            payload: payload, container: container, center: center,
            globalThresholdSeconds: 0, dedupeStore: store
        )

        #expect(handled)
        let requests = await center.addedRequests
        #expect(requests.count == 1)

        let request = try #require(requests.first)
        #expect(request.identifier == "shift-\(ids.vendorID.uuidString)")
        #expect(request.content.title == "Timeline Update")
        // Rich body produced by VendorShiftNotificationContent: delta + next block.
        #expect(request.content.body.contains("+15 min"))
        #expect(request.content.body.contains("First Dance"))
        let routedEventID = request.content.userInfo[VendorShiftNotificationContent.eventIDKey] as? String
        #expect(routedEventID == ids.eventID.uuidString)
    }

    @Test("a push for an event not on this device posts nothing")
    func unknownEventPostsNothing() async throws {
        let container = try makeContainer()
        try seed(into: ModelContext(container))
        let center = MockNotificationCenter()

        let payload = RemoteShiftPushHandler.ShiftPushPayload(
            eventID: UUID(), eventVendorID: UUID(), delta: 900
        )

        let handled = await RemoteShiftPushHandler.handle(
            payload: payload, container: container, center: center, globalThresholdSeconds: 0
        )

        #expect(!handled)
        #expect(await center.addedRequests.isEmpty)
    }

    @Test("parse returns nil for a non-shift push")
    func parseIgnoresNonShiftPush() {
        #expect(RemoteShiftPushHandler.parse(["aps": ["content-available": 1]]) == nil)
    }

    @Test("parse extracts the event id, vendor id, and delta")
    func parseExtractsFields() throws {
        let eventID = UUID()
        let vendorID = UUID()
        let payload = try #require(RemoteShiftPushHandler.parse([
            VendorShiftNotificationContent.eventIDKey: eventID.uuidString,
            "event_vendor_id": vendorID.uuidString,
            "pending_shift_delta": 900.0,
        ]))
        #expect(payload.eventID == eventID)
        #expect(payload.eventVendorID == vendorID)
        #expect(payload.delta == 900)
    }
}
