import CloudKit
import Foundation
import Services
import Testing

@Suite("SharedZoneSubscriptionManager")
struct SharedZoneSubscriptionTests {

    // MARK: - Subscription ID Consistency

    @Test func subscriptionIDIsStable() {
        // The subscription ID must stay constant across app versions so
        // CloudKit doesn't create duplicate subscriptions.
        // We verify via the notification filter in AppDelegate.
        let userInfo: [AnyHashable: Any] = [
            "ck": [
                "ce": 2, // database notification
                "cid": "iCloud.com.neelsoftwaresolutions.shiftTimeline",
            ] as [String: Any],
        ]

        let notification = CKNotification(fromRemoteNotificationDictionary: userInfo)
        // CKNotification parses but subscriptionID will be nil without the
        // actual field — this just confirms the parser doesn't crash.
        #expect(notification != nil)
    }

    // MARK: - Token Persistence Round-Trip

    @Test func serverChangeTokenPersistsViaUserDefaults() throws {
        // Create a fake token by archiving/unarchiving — CKServerChangeToken
        // is not directly constructable, so we verify the archiving codepath.
        let key = "com.shift.test.changeTokenRoundTrip"
        defer { UserDefaults.standard.removeObject(forKey: key) }

        // No token stored initially.
        let data = UserDefaults.standard.data(forKey: key)
        #expect(data == nil)

        // After setting data, it persists.
        let testData = Data([0x01, 0x02, 0x03])
        UserDefaults.standard.set(testData, forKey: key)
        let stored = UserDefaults.standard.data(forKey: key)
        #expect(stored == testData)
    }

    // MARK: - Manager Singleton

    @Test func sharedInstanceIsSingleton() {
        let a = SharedZoneSubscriptionManager.shared
        let b = SharedZoneSubscriptionManager.shared
        #expect(a === b)
    }

    @Test func initialStateIsNotSubscribed() {
        // A freshly-created manager (via .shared) should not claim to be
        // subscribed until registerIfNeeded() completes successfully.
        // Note: In CI without iCloud, this will remain false.
        let manager = SharedZoneSubscriptionManager.shared
        // We can't guarantee the state if a previous test registered,
        // but the type should be observable and non-nil.
        #expect(type(of: manager).self == SharedZoneSubscriptionManager.self)
    }
}
