import UIKit
import CloudKit
import os

/// Window-scene delegate that receives CloudKit share-accept callbacks for
/// SwiftUI scene-based apps. When a vendor taps an iMessage share link, iOS
/// dispatches `userDidAcceptCloudKitShareWith` to this method — **not** to
/// `UIApplicationDelegate.application(_:userDidAcceptCloudKitShareWith:)`.
///
/// All real work is delegated to `AppDelegate.handleAcceptedShare(metadata:)`
/// so the scene and application paths stay byte-for-byte equivalent.
///
/// Design notes:
/// - Inherits from `NSObject` to guarantee the ObjC runtime can instantiate
///   this class via `NSClassFromString` when iOS resolves the scene manifest.
///   Without NSObject, Swift's Release-build whole-module optimization can
///   dead-strip the class entirely since nothing in Swift code holds a direct
///   reference — only the Info.plist string does.
/// - `@objc(SHIFTSceneDelegate)` pins the exported ObjC symbol name, matching
///   the `$(PRODUCT_MODULE_NAME).SHIFTSceneDelegate` entry in UISceneConfigurations.
/// - No `@MainActor` on the class or method: UIKit dispatches delegate callbacks
///   on the main thread already, and actor isolation on the class declaration
///   can suppress implicit @objc bridging in optimised builds.
@objc(SHIFTSceneDelegate)
final class SHIFTSceneDelegate: NSObject, UIWindowSceneDelegate {

    private static let logger = Logger(
        subsystem: "com.neelsoftwaresolutions.shiftTimeline",
        category: "CloudSharing"
    )

    var window: UIWindow?

    @objc func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        Self.logger.info("Scene delegate received share-accept metadata for zone: \(cloudKitShareMetadata.rootRecordID.zoneID.zoneName)")
        Task { @MainActor in
            AppDelegate.handleAcceptedShare(metadata: cloudKitShareMetadata)
        }
    }
}
