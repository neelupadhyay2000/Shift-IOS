import UIKit
import CloudKit
import os

/// Window-scene delegate for CloudKit share-accept callbacks.
/// Delegates all work to `AppDelegate.handleAcceptedShare(metadata:)`.
/// Must inherit `NSObject` so iOS can instantiate via `NSClassFromString` from Info.plist.
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
        Self.logger.info("Scene delegate received share-accept metadata for zone: \(cloudKitShareMetadata.share.recordID.zoneID.zoneName)")
        Task { @MainActor in
            AppDelegate.handleAcceptedShare(metadata: cloudKitShareMetadata)
        }
    }
}
