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

    /// Quick-access grace window. Returning to the foreground within this many
    /// seconds of backgrounding skips re-auth, so planners running an event can
    /// pop in and out (camera, texts, notes) without a Face ID / passcode every
    /// time. Cold launch has no recorded background time, so it always re-auths.
    private static let graceInterval: TimeInterval = 300  // 5 minutes

    /// When the app last entered the background, or `nil` on a fresh launch /
    /// once a foreground transition has consumed it.
    private var lastBackgroundedAt: Date?

    /// Locked from process start whenever a passcode exists, so content is
    /// never visible on cold launch. UI test runs skip the lock entirely.
    private(set) var isLocked: Bool

    /// Privacy cover shown *only* while the app is backgrounded, so the
    /// app-switcher snapshot never exposes content. Unlike ``isLocked`` it needs
    /// no authentication and is cleared the instant the app returns — it exists
    /// purely so a quick return doesn't have to flash the passcode screen.
    private(set) var isObscured = false

    /// Mirrors the Keychain so the root gate can observe the transition
    /// out of `PasscodeSetupView` after the first sign-in.
    private(set) var hasPasscode: Bool

    /// `true` from the moment a sign-in is observed until the account's
    /// passcode record has been fetched (or the fetch failed). The root gate
    /// holds its loading view during this window instead of flashing the
    /// passcode-setup UI at a user whose passcode is about to be restored.
    private(set) var isRestoringRecord = false

    private init() {
        let hasCode = PasscodeStore().hasPasscode
        hasPasscode = hasCode
        isLocked = hasCode && !shiftTimelineApp.isUITestMode
    }

    /// Defaults to ON (unset = enabled) — Face ID is the intended fast path;
    /// the Account screen toggle opts out. The first scan triggers the
    /// system's own Face ID permission prompt.
    var isFaceIDEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.faceIDEnabledKey) as? Bool ?? true
    }

    /// Why biometrics can or can't be used right now.
    ///
    /// `canEvaluatePolicy` answers `false` for four very different reasons, and
    /// collapsing them into one Bool is what made a denied permission prompt look
    /// like a broken app: the Settings toggle greyed out and the lock screen fell
    /// straight through to the keypad, with nothing on screen explaining either.
    /// Two of the four are recoverable by the user, so the reason has to survive.
    /// `nonisolated` because ``biometryStatus()`` is, and a nested type would
    /// otherwise infer `AppLock`'s `@MainActor` isolation and fail to cross back.
    nonisolated enum BiometryStatus: Equatable {
        /// Ready to use.
        case available(LABiometryType)
        /// Hardware exists, but the user has no face/finger enrolled.
        case notEnrolled(LABiometryType)
        /// The user answered "Don't Allow" to our `NSFaceIDUsageDescription`
        /// prompt. Recoverable in iOS Settings → SHIFT.
        case denied(LABiometryType)
        /// Too many failed scans. Recoverable by unlocking the device with its
        /// passcode once.
        case lockedOut(LABiometryType)
        /// No biometric hardware, or an error we don't model.
        case unsupported

        var isAvailable: Bool { if case .available = self { return true } else { return false } }

        private var biometryType: LABiometryType? {
            switch self {
            case .available(let type), .notEnrolled(let type),
                 .denied(let type), .lockedOut(let type):
                return type
            case .unsupported:
                return nil
            }
        }

        /// What to call it on screen. Never hard-code "Face ID": iPhone SE and
        /// several iPads are Touch ID.
        var name: String {
            switch biometryType {
            case .faceID: String(localized: "Face ID")
            case .touchID: String(localized: "Touch ID")
            case .opticID: String(localized: "Optic ID")
            default: String(localized: "Biometrics")
            }
        }

        /// Derived from the hardware type, not from `name` — a localized build
        /// must not fall back to the wrong glyph.
        var symbolName: String {
            switch biometryType {
            case .faceID: "faceid"
            case .touchID: "touchid"
            case .opticID: "opticid"
            default: "lock.shield"
            }
        }

        /// Whether iOS Settings can fix it — drives the "Open Settings" affordance.
        var isResolvableInSettings: Bool {
            switch self {
            case .denied, .notEnrolled: return true
            case .available, .lockedOut, .unsupported: return false
            }
        }

        /// Why the toggle is off, in the user's terms. `nil` when available.
        var explanation: String? {
            switch self {
            case .available:
                return nil
            case .denied:
                return String(localized: "\(name) is turned off for SHIFT. Turn it on in iOS Settings to unlock without typing your passcode.")
            case .notEnrolled:
                return String(localized: "\(name) isn't set up on this device yet. Add it in iOS Settings.")
            case .lockedOut:
                return String(localized: "\(name) is locked after too many failed attempts. Unlock this iPhone with its passcode once to re-enable it.")
            case .unsupported:
                return String(localized: "This device doesn't support biometric unlock.")
            }
        }
    }

    /// The live biometric state. Cheap enough to call on every scene activation,
    /// which is what lets the toggle recover the moment the user returns from iOS
    /// Settings having granted permission.
    ///
    /// `LAContext.biometryType` is only populated *after* `canEvaluatePolicy` runs
    /// on that same context, so the order here matters.
    nonisolated static func biometryStatus() -> BiometryStatus {
        let context = LAContext()
        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        let type = context.biometryType

        if canEvaluate { return .available(type) }

        guard let error, error.domain == LAErrorDomain else { return .unsupported }

        switch LAError.Code(rawValue: error.code) {
        case .biometryNotEnrolled:
            return .notEnrolled(type)
        case .biometryLockout:
            return .lockedOut(type)
        case .biometryNotAvailable:
            // iOS returns -6 for BOTH "this device has no biometric hardware" and
            // "the user tapped Don't Allow on our usage prompt". The only thing
            // separating them is biometryType, which stays `.none` when hardware
            // is absent but still reports the real sensor when the app was merely
            // denied. Get this wrong and an iPhone with no Face ID tells its owner
            // to go re-enable Face ID.
            return type == .none ? .unsupported : .denied(type)
        default:
            return .unsupported
        }
    }


    // MARK: - Setup / teardown

    /// Stores the passcode created in ``PasscodeSetupView`` and admits the user.
    func setPasscode(_ passcode: String) {
        store.set(passcode)
        hasPasscode = true
        isLocked = false
    }

    /// The opaque Keychain record, for mirroring to `app_passcodes`.
    func currentRecord() -> Data? {
        store.currentRecord()
    }

    /// Installs a server-restored record after OTP sign-in: the user's
    /// previous passcode works immediately and the setup screen is skipped.
    /// Leaves `isLocked` untouched — the user just authenticated via OTP.
    func installRestoredRecord(_ record: Data) {
        store.setRecord(record)
        hasPasscode = true
    }

    /// Called synchronously when a sign-in event is observed, before the
    /// first suspension point, so the gate never renders the setup screen
    /// ahead of the restore attempt.
    func beginAccountRestore() {
        guard !hasPasscode else { return }
        isRestoringRecord = true
    }

    func finishAccountRestore() {
        isRestoringRecord = false
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

    /// Leaving the foreground. We deliberately do **not** lock here — locking
    /// eagerly is what made the passcode screen flash on every quick return.
    /// Instead we obscure the app-switcher snapshot for privacy and stamp the
    /// time so the next foreground transition can decide whether to re-auth.
    func enterBackground() {
        guard hasPasscode, !shiftTimelineApp.isUITestMode else { return }
        // If the lock screen is already up (cold launch, not yet authenticated),
        // leave it up and do NOT stamp — returning must never grant a grace
        // unlock, or app-switching would bypass authentication entirely.
        guard !isLocked else { return }
        lastBackgroundedAt = Date()
        isObscured = true
    }

    /// Returning to the foreground. Drop the privacy cover, and require the
    /// passcode **only** if the app was backgrounded beyond ``graceInterval``.
    /// A quick return (within grace) goes straight back to the app — the lock
    /// screen never appears. Cold launch has no stamp, so ``isLocked`` (set at
    /// init) simply stands. The stamp is consumed either way.
    func enterForeground() {
        isObscured = false
        guard hasPasscode, let backgroundedAt = lastBackgroundedAt else { return }
        lastBackgroundedAt = nil
        if Date().timeIntervalSince(backgroundedAt) >= Self.graceInterval {
            isLocked = true
        }
    }

    /// Keypad path. Returns `false` (and stays locked) on a wrong code.
    func unlock(with passcode: String) -> Bool {
        guard store.validate(passcode) else { return false }
        isLocked = false
        return true
    }

    /// How a biometric attempt ended, so the lock screen can distinguish
    /// "the system killed the prompt mid-transition" (retry silently) from
    /// "the user declined or failed" (fall back to the keypad).
    enum BiometricOutcome {
        case unlocked
        /// The prompt never reached the user — system/app cancellation,
        /// typically because a presentation transition was still in flight.
        case interrupted
        /// The user cancelled, failed, or biometrics are unusable.
        case declined
    }

    /// Face ID fast path — biometrics only; the app passcode (not the device
    /// passcode) is the fallback. Concurrent calls coalesce.
    @discardableResult
    func unlockWithBiometrics() async -> BiometricOutcome {
        guard isLocked else { return .unlocked }
        guard isFaceIDEnabled, !isAuthenticating else { return .declined }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: String(localized: "Unlock SHIFT")
            )
            guard success else { return .declined }
            isLocked = false
            return .unlocked
        } catch let error as LAError {
            switch error.code {
            case .systemCancel, .appCancel, .notInteractive:
                return .interrupted
            default:
                return .declined
            }
        } catch {
            return .declined
        }
    }
}
