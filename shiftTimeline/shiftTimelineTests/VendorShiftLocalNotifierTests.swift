import Foundation
import UserNotifications
import SwiftData
import Testing
import Models
import Services
@testable import shiftTimeline

// MARK: - Mock

/// Records every `UNNotificationRequest` passed to `add(_:)`.
/// Thread-safe via actor isolation — Swift Testing may call
/// `processAndNotify` off the main actor.
private actor MockNotificationCenter: VendorNotificationScheduling {
    private(set) var addedRequests: [UNNotificationRequest] = []
    var shouldThrow = false

    nonisolated func add(_ request: UNNotificationRequest) async throws {
        if await shouldThrow { throw URLError(.unknown) }
        await record(request)
    }

    private func record(_ request: UNNotificationRequest) {
        addedRequests.append(request)
    }

    func reset() {
        addedRequests = []
        shouldThrow = false
    }
}

// MARK: - Helpers

private func makeVendor(
    name: String = "Alice",
    threshold: TimeInterval = 600,      // 10 min
    pendingDelta: TimeInterval? = 900,  // 15 min
    acknowledged: Bool = false
) -> VendorModel {
    let vendor = VendorModel(name: name, role: .photographer, notificationThreshold: threshold)
    vendor.hasAcknowledgedLatestShift = acknowledged
    vendor.pendingShiftDelta = pendingDelta
    return vendor
}

/// Builds an in-memory `EventModel` with the given vendors attached.
/// Uses an ephemeral `ModelContainer` so VendorModel `@Model` objects are
/// in a valid SwiftData context for the duration of the test.
@discardableResult
private func makeEvent(vendors: [VendorModel]) throws -> (EventModel, ModelContainer) {
    let schema = Schema([EventModel.self, VendorModel.self, TimelineTrack.self, TimeBlockModel.self, ShiftRecord.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try ModelContainer(for: schema, configurations: [config])
    let ctx = ModelContext(container)

    let event = EventModel(title: "Test Event", date: .now, latitude: 0, longitude: 0)
    ctx.insert(event)
    for vendor in vendors {
        ctx.insert(vendor)
        vendor.event = event
    }
    try ctx.save()
    return (event, container)
}

// MARK: - Suite

@Suite("VendorShiftLocalNotifier — request posting & acknowledgment")
struct VendorShiftLocalNotifierTests {

    // MARK: - Correct identifier, title, body

    @Test func postsRequestWithCorrectIdentifierAndTitle() async throws {
        let vendor = makeVendor()
        let (event, _) = try makeEvent(vendors: [vendor])
        let center = MockNotificationCenter()

        await VendorShiftLocalNotifier.processAndNotify(
            event: event,
            center: center,
            globalThresholdSeconds: 0   // global floor = 0 so vendor threshold governs
        )

        let requests = await center.addedRequests
        #expect(requests.count == 1)

        let req = try #require(requests.first)
        // Identifier must be deterministic and vendor-scoped
        #expect(req.identifier == "shift-\(vendor.id.uuidString)")
        // Title is the localised "Timeline Update" string
        #expect(req.content.title == "Timeline Update")
        // Body must be non-empty (content is delegated to VendorShiftNotificationContent)
        #expect(!req.content.body.isEmpty)
        // Must carry the event ID for tap routing
        let eventIDInPayload = req.content.userInfo[VendorShiftNotificationContent.eventIDKey] as? String
        #expect(eventIDInPayload == event.id.uuidString)
        // Trigger must be nil (immediate delivery)
        #expect(req.trigger == nil)
    }

    // MARK: - Threading (one request per vendor, not per block)

    @Test func postsOneRequestPerVendorAboveThreshold() async throws {
        let v1 = makeVendor(name: "Alice", pendingDelta: 900)   // above threshold
        let v2 = makeVendor(name: "Bob",   pendingDelta: 900)   // above threshold
        let v3 = makeVendor(name: "Charlie", pendingDelta: 60)  // below threshold
        let (event, _) = try makeEvent(vendors: [v1, v2, v3])
        let center = MockNotificationCenter()

        await VendorShiftLocalNotifier.processAndNotify(
            event: event,
            center: center,
            globalThresholdSeconds: 600  // 10 min global floor
        )

        let requests = await center.addedRequests
        // Only Alice and Bob exceed threshold; Charlie does not
        #expect(requests.count == 2)
        let ids = requests.map(\.identifier)
        #expect(ids.contains("shift-\(v1.id.uuidString)"))
        #expect(ids.contains("shift-\(v2.id.uuidString)"))
        #expect(!ids.contains("shift-\(v3.id.uuidString)"))
    }

    // MARK: - hasAcknowledgedLatestShift resets on shift

    @Test func hasAcknowledgedLatestShiftIsFalseAfterNotification() async throws {
        // Start with vendor already acknowledged — a new shift should flip it back.
        let vendor = makeVendor(pendingDelta: 900, acknowledged: true)
        let (event, _) = try makeEvent(vendors: [vendor])
        let center = MockNotificationCenter()

        await VendorShiftLocalNotifier.processAndNotify(
            event: event,
            center: center,
            globalThresholdSeconds: 0
        )

        #expect(vendor.hasAcknowledgedLatestShift == false)
    }

    @Test func hasAcknowledgedLatestShiftFlipsToTrueOnUserTap() async throws {
        // Simulate the vendor tapping the acknowledgment banner.
        let vendor = makeVendor(acknowledged: false)
        vendor.hasAcknowledgedLatestShift = true   // banner tap writes this

        #expect(vendor.hasAcknowledgedLatestShift == true)
    }

    // MARK: - No duplicate when threshold not exceeded

    @Test func doesNotPostWhenDeltaBelowBothThresholds() async throws {
        // Delta is 1 min, thresholds are both 10 min → no notification.
        let vendor = makeVendor(threshold: 600, pendingDelta: 60)
        let (event, _) = try makeEvent(vendors: [vendor])
        let center = MockNotificationCenter()

        await VendorShiftLocalNotifier.processAndNotify(
            event: event,
            center: center,
            globalThresholdSeconds: 600
        )

        let requests = await center.addedRequests
        #expect(requests.isEmpty)
    }

    @Test func dedupesRepeatedPostsForSameShift() async throws {
        // processVendorShiftNotifications runs on every app-active / 30s poll.
        // Because pendingShiftDelta is preserved (the in-app banner reads it),
        // the notifier must dedupe so the vendor isn't re-alerted for the same
        // shift on every scan. Two calls with the same delta → exactly 1 post.
        let store = try #require(UserDefaults(suiteName: "test-dedupe-\(UUID().uuidString)"))
        let vendor = makeVendor(pendingDelta: 900)
        let (event, _) = try makeEvent(vendors: [vendor])
        let center = MockNotificationCenter()

        await VendorShiftLocalNotifier.processAndNotify(
            event: event, center: center, globalThresholdSeconds: 0, dedupeStore: store
        )
        await VendorShiftLocalNotifier.processAndNotify(
            event: event, center: center, globalThresholdSeconds: 0, dedupeStore: store
        )

        let requests = await center.addedRequests
        #expect(requests.count == 1)
        #expect(requests.first?.identifier == "shift-\(vendor.id.uuidString)")
    }

    @Test func postsAgainWhenDeltaChanges() async throws {
        // A new shift produces a different cumulative delta, which must re-alert.
        let store = try #require(UserDefaults(suiteName: "test-dedupe-\(UUID().uuidString)"))
        let vendor = makeVendor(pendingDelta: 900)
        let (event, _) = try makeEvent(vendors: [vendor])
        let center = MockNotificationCenter()

        await VendorShiftLocalNotifier.processAndNotify(
            event: event, center: center, globalThresholdSeconds: 0, dedupeStore: store
        )
        vendor.pendingShiftDelta = 1500   // a further shift
        await VendorShiftLocalNotifier.processAndNotify(
            event: event, center: center, globalThresholdSeconds: 0, dedupeStore: store
        )

        let requests = await center.addedRequests
        #expect(requests.count == 2)
    }

    // MARK: - Vendor with no pendingShiftDelta is skipped

    @Test func skipsVendorWithNilPendingDelta() async throws {
        let vendor = makeVendor(pendingDelta: nil)
        let (event, _) = try makeEvent(vendors: [vendor])
        let center = MockNotificationCenter()

        await VendorShiftLocalNotifier.processAndNotify(
            event: event,
            center: center,
            globalThresholdSeconds: 0
        )

        let requests = await center.addedRequests
        #expect(requests.isEmpty)
    }
}
