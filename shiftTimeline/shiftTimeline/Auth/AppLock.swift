import LocalAuthentication
import SwiftUI

/// Device access layer over the app: a mandatory six-digit passcode (created
/// on first sign-in via ``PasscodeSetupView``) required on every app open,
/// with optional Face ID / Touch ID as the fast path.
///
/// This is separate from the account layer: email OTP proves identity once
/// per device and the Supabase session lives on in the Keychain; the passcode
/// then guards entry without ever re-running OTP. Face ID uses the
/// biometrics-only policy — the app passcode (not the device passcode) is the
/// fallback. Sign-out wipes the passcode so a new sign-in re-creates it.
@Observable
@MainActor
final class AppLock {

    static let shared = AppLock()

    /// Face ID preference. (Key name predates the passcode system.)
    static let faceIDEnabledKey = "appLock.enabled"

    private let store = PasscodeStore()
    private var isAuthenticating = false

    /// Locked from process start whenever a passcode exists, so content is
    /// never visible on cold launch. UI test runs skip the lock entirely.
    private(set) var isLocked: Bool

    /// Mirrors the Keychain so the root gate can observe the transition
    /// out of `PasscodeSetupView` after the first sign-in.
    private(set) var hasPasscode: Bool

    private init() {
        let hasCode = PasscodeStore().hasPasscode
        hasPasscode = hasCode
        isLocked = hasCode && !shiftTimelineApp.isUITestMode
    }

    var isFaceIDEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.faceIDEnabledKey)
    }

    /// `true` when the device offers Face ID / Touch ID (the Settings toggle
    /// and the post-setup offer are hidden otherwise).
    nonisolated static var isBiometricsAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    // MARK: - Setup / teardown

    /// Stores the passcode created in ``PasscodeSetupView`` and admits the user.
    func setPasscode(_ passcode: String) {
        store.set(passcode)
        hasPasscode = true
        isLocked = false
    }

    /// Sign-out and account deletion wipe the device passcode and Face ID
    /// preference: the next sign-in (any account) re-authenticates with OTP
    /// and creates a fresh passcode.
    func resetForSignOut() {
        store.clear()
        UserDefaults.standard.removeObject(forKey: Self.faceIDEnabledKey)
        hasPasscode = false
        isLocked = false
    }

    // MARK: - Lock / unlock

    /// Re-locks when the app leaves the foreground.
    func lockOnBackground() {
        guard hasPasscode, !shiftTimelineApp.isUITestMode else { return }
        isLocked = true
    }

    /// Keypad path. Returns `false` (and stays locked) on a wrong code.
    func unlock(with passcode: String) -> Bool {
        guard store.validate(passcode) else { return false }
        isLocked = false
        return true
    }

    /// Face ID fast path — biometrics only; a cancelled or failed scan falls
    /// back to the keypad, never to the device passcode. Concurrent calls
    /// coalesce.
    func unlockWithBiometrics() async {
        guard isLocked, isFaceIDEnabled, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: String(localized: "Unlock SHIFT")
            )
            if success { isLocked = false }
        } catch {
            // Cancelled or unavailable — the keypad remains.
        }
    }
}
