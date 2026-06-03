import UIKit

/// Window-scene delegate. CKShare callbacks have been removed (SHIFT-531);
/// the class is retained so `AppDelegate.application(_:configurationForConnecting:options:)`
/// can wire it as the scene delegate class without an ObjC name-string lookup.
///
/// - `@objc(SHIFTSceneDelegate)` pins the exported ObjC symbol name, matching
///   the `$(PRODUCT_MODULE_NAME).SHIFTSceneDelegate` entry in UISceneConfigurations.
/// - Inherits from `NSObject` so the ObjC runtime can instantiate this class
///   in Release builds where Swift's WMO would otherwise dead-strip it.
@objc(SHIFTSceneDelegate)
final class SHIFTSceneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?
}
