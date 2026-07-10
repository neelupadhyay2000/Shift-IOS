import LocalAuthentication
import Testing
@testable import shiftTimeline

/// `AppLock.BiometryStatus` exists because `canEvaluatePolicy` collapses four very
/// different situations into `false`. Two of them the user can fix; two they can't.
/// Flattening them to a Bool is what turned a denied permission prompt into a
/// greyed-out toggle and a lock screen that skipped straight to the keypad, with
/// nothing on screen saying why.
///
/// `biometryStatus()` itself can't be unit-tested (it reads real device state), so
/// these pin the classification's *consequences* — the parts the UI branches on.
@Suite("Biometry status")
@MainActor
struct BiometryStatusTests {

    // MARK: - Availability

    @Test("only .available is usable")
    func onlyAvailableIsUsable() {
        #expect(AppLock.BiometryStatus.available(.faceID).isAvailable)
        #expect(AppLock.BiometryStatus.denied(.faceID).isAvailable == false)
        #expect(AppLock.BiometryStatus.notEnrolled(.faceID).isAvailable == false)
        #expect(AppLock.BiometryStatus.lockedOut(.faceID).isAvailable == false)
        #expect(AppLock.BiometryStatus.unsupported.isAvailable == false)
    }

    // MARK: - Naming

    /// Never hard-code "Face ID": iPhone SE and several iPads are Touch ID, and
    /// telling a Touch ID owner to enable Face ID is worse than saying nothing.
    @Test("the name follows the hardware, not the platform")
    func nameFollowsHardware() {
        #expect(AppLock.BiometryStatus.available(.faceID).name == "Face ID")
        #expect(AppLock.BiometryStatus.available(.touchID).name == "Touch ID")
        #expect(AppLock.BiometryStatus.available(.opticID).name == "Optic ID")
        #expect(AppLock.BiometryStatus.unsupported.name == "Biometrics")
    }

    /// The glyph is derived from the hardware type, never from the (localizable)
    /// name — a translated build must not fall through to the wrong symbol.
    @Test("the SF Symbol follows the hardware too")
    func symbolFollowsHardware() {
        #expect(AppLock.BiometryStatus.available(.faceID).symbolName == "faceid")
        #expect(AppLock.BiometryStatus.available(.touchID).symbolName == "touchid")
        #expect(AppLock.BiometryStatus.available(.opticID).symbolName == "opticid")
        #expect(AppLock.BiometryStatus.unsupported.symbolName == "lock.shield")
    }

    @Test("a denied Touch ID device is named Touch ID, not Face ID")
    func deniedKeepsItsHardwareName() {
        #expect(AppLock.BiometryStatus.denied(.touchID).name == "Touch ID")
        #expect(AppLock.BiometryStatus.denied(.touchID).symbolName == "touchid")
    }

    // MARK: - Recoverability

    /// Drives the "Open Settings" link. Lockout is NOT resolvable there — it clears
    /// by unlocking the device with its passcode — and offering a Settings deep
    /// link for it would send the user somewhere that can't help.
    @Test("only denied and not-enrolled are fixable in iOS Settings")
    func settingsResolvability() {
        #expect(AppLock.BiometryStatus.denied(.faceID).isResolvableInSettings)
        #expect(AppLock.BiometryStatus.notEnrolled(.faceID).isResolvableInSettings)
        #expect(AppLock.BiometryStatus.lockedOut(.faceID).isResolvableInSettings == false)
        #expect(AppLock.BiometryStatus.unsupported.isResolvableInSettings == false)
        #expect(AppLock.BiometryStatus.available(.faceID).isResolvableInSettings == false)
    }

    // MARK: - Explanation

    @Test("an available sensor needs no explanation")
    func availableHasNoExplanation() {
        #expect(AppLock.BiometryStatus.available(.faceID).explanation == nil)
    }

    /// Every unavailable state must say something. A disabled toggle with no
    /// caption is the original bug.
    @Test("every unavailable state explains itself")
    func everyUnavailableStateExplainsItself() {
        let unavailable: [AppLock.BiometryStatus] = [
            .denied(.faceID), .notEnrolled(.faceID), .lockedOut(.faceID), .unsupported,
        ]
        for status in unavailable {
            #expect(status.explanation?.isEmpty == false, "\(status) has no explanation")
        }
    }

    /// The explanation names the sensor, so a Touch ID user isn't told about a
    /// Face ID setting that doesn't exist on their phone.
    @Test("the explanation names the actual sensor")
    func explanationNamesTheSensor() throws {
        let denied = try #require(AppLock.BiometryStatus.denied(.touchID).explanation)
        #expect(denied.contains("Touch ID"))
        #expect(denied.contains("Face ID") == false)
    }

    /// Lockout is recovered by unlocking the *device*, not by any app setting.
    @Test("lockout tells the user to unlock the device, not to open Settings")
    func lockoutExplanationPointsAtTheDevice() throws {
        let lockedOut = try #require(AppLock.BiometryStatus.lockedOut(.faceID).explanation)
        #expect(lockedOut.localizedCaseInsensitiveContains("passcode"))
    }
}
