import Testing
import Foundation

/// Verifies the app's `Info.plist` registers `SHIFTSceneDelegate` so iOS routes
/// `userDidAcceptCloudKitShareWith` to the scene delegate. Without this entry,
/// scene-based SwiftUI apps silently fall back to the application-delegate path,
/// which iOS no longer invokes for share acceptance — vendor share links open
/// the app to the Events tab and do nothing.
@Suite("Info.plist scene manifest")
struct InfoPlistSceneManifestTests {

    @Test("UIApplicationSceneManifest registers SHIFTSceneDelegate")
    func registersSceneDelegate() throws {
        let info = try #require(Bundle.main.infoDictionary)
        let manifest = try #require(info["UIApplicationSceneManifest"] as? [String: Any])
        let supportsMultiple = manifest["UIApplicationSupportsMultipleScenes"] as? Bool
        #expect(supportsMultiple == false)

        let configurations = try #require(manifest["UISceneConfigurations"] as? [String: Any])
        let appRole = try #require(configurations["UIWindowSceneSessionRoleApplication"] as? [[String: Any]])
        let first = try #require(appRole.first)
        let className = try #require(first["UISceneDelegateClassName"] as? String)
        #expect(className.hasSuffix(".SHIFTSceneDelegate"))
    }
}
