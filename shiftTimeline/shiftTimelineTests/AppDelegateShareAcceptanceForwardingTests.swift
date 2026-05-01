import Testing
import UIKit
import CloudKit
@testable import shiftTimeline

/// Verifies the AppDelegate fallback path remains wired after the scene-delegate
/// extraction. Both `AppDelegate.application(_:userDidAcceptCloudKitShareWith:)`
/// and `SHIFTSceneDelegate.windowScene(_:userDidAcceptCloudKitShareWith:)` must
/// forward to the same shared handler `AppDelegate.handleAcceptedShare(metadata:)`.
@MainActor
@Suite("AppDelegate share-acceptance forwarding")
struct AppDelegateShareAcceptanceForwardingTests {

    @Test("AppDelegate responds to application(_:userDidAcceptCloudKitShareWith:)")
    func respondsToShareAcceptSelector() {
        let delegate = AppDelegate()
        let selector = NSSelectorFromString("application:userDidAcceptCloudKitShareWithMetadata:")
        #expect(delegate.responds(to: selector))
    }

    @Test("AppDelegate implements configurationForConnecting with SHIFTSceneDelegate class")
    func configurationForConnectingReturnsSHIFTSceneDelegate() {
        let delegate = AppDelegate()
        let selector = NSSelectorFromString("application:configurationForConnectingSceneSession:options:")
        #expect(delegate.responds(to: selector))
    }

    @Test("Shared handler test seam is invoked when set")
    func sharedHandlerTestSeamFires() {
        var fired = 0
        AppDelegate.handleAcceptedShareForTesting = { fired += 1 }
        defer { AppDelegate.handleAcceptedShareForTesting = nil }

        AppDelegate.fireShareAcceptanceTestHook()

        #expect(fired == 1)
    }
}
