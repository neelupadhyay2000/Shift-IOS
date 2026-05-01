import Testing
import UIKit
import CloudKit
@testable import shiftTimeline

/// Verifies the scene-based share-acceptance routing introduced by
/// `fix-vendor-share-acceptance`.
///
/// `CKShare.Metadata` has no public initializer, so we cannot drive the
/// real method end-to-end from a unit test. These tests cover the
/// structural invariants that, when broken, silently disable share
/// acceptance on real devices:
/// 1. `SHIFTSceneDelegate` exists and conforms to `UIWindowSceneDelegate`.
/// 2. It exposes `windowScene(_:userDidAcceptCloudKitShareWith:)` to the
///    Objective-C runtime so iOS can dispatch to it.
@MainActor
@Suite("SHIFTSceneDelegate")
struct SHIFTSceneDelegateTests {

    @Test("Instantiates and conforms to UIWindowSceneDelegate")
    func conformsToUIWindowSceneDelegate() {
        let delegate = SHIFTSceneDelegate()
        #expect((delegate as Any) is UIWindowSceneDelegate)
    }

    @Test("Inherits from NSObject (required for ObjC class resolution via NSClassFromString)")
    func inheritsFromNSObject() {
        let delegate = SHIFTSceneDelegate()
        #expect((delegate as Any) is NSObject)
    }

    @Test("Responds to windowScene(_:userDidAcceptCloudKitShareWith:)")
    func respondsToShareAcceptSelector() {
        let delegate = SHIFTSceneDelegate()
        let selector = NSSelectorFromString("windowScene:userDidAcceptCloudKitShareWithMetadata:")
        #expect(delegate.responds(to: selector))
    }
}
