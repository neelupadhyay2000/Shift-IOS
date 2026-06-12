import LocalAuthentication
import SwiftUI

/// Optional biometric privacy lock (Settings → Privacy & Security).
///
/// When enabled, the app locks on cold launch and whenever it leaves the
/// foreground; unlocking uses `.deviceOwnerAuthentication` — Face ID / Touch ID
/// with the system passcode as fallback, so a failed scan never strands the
/// user. This is purely a privacy shield over the UI: the Supabase session in
/// the Keychain is untouched, so unlocking never re-runs the OTP flow.
@Observable
@MainActor
final class AppLock {

    static let shared = AppLock()

    /// UserDefaults key for the user preference (Settings toggle).
    static let enabledKey = "appLock.enabled"

    /// Locked from process start when the preference is on, so the content
    /// behind the lock is never visible on cold launch. UI test runs skip the
    /// lock — they can't answer a biometric prompt.
    private(set) var isLocked: Bool

    private var isAuthenticating = false

    private init() {
        isLocked = UserDefaults.standard.bool(forKey: Self.enabledKey)
            && !shiftTimelineApp.isUITestMode
    }

    /// `true` when the device can evaluate biometrics or a passcode —
    /// the Settings toggle is disabled when this is false.
    nonisolated static var isAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    /// Re-locks when the app leaves the foreground (scene → background).
    func lockIfEnabled() {
        guard UserDefaults.standard.bool(forKey: Self.enabledKey) else { return }
        isLocked = true
    }

    /// Prompts Face ID / Touch ID (passcode fallback). Safe to call repeatedly;
    /// concurrent calls coalesce. Stays locked on failure or cancel — the lock
    /// screen's button retries.
    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: String(localized: "Unlock SHIFT")
            )
            if success { isLocked = false }
        } catch {
            // User cancelled or biometry unavailable — remain locked.
        }
    }
}

// MARK: - Lock screen

/// Full-screen cover shown while `AppLock.isLocked` — the same brand wash as
/// sign-in so launch always opens on a SHIFT-branded surface.
struct AppLockScreen: View {
    let unlock: () async -> Void

    var body: some View {
        ZStack {
            SignInBrandBackground()
            VStack(spacing: 32) {
                Spacer()
                SignInStepBadge(systemImage: "lock.fill")
                Text(String(localized: "SHIFT is locked"))
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    Task { await unlock() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "faceid")
                        Text(String(localized: "Unlock"))
                    }
                }
                .buttonStyle(SignInPrimaryButtonStyle())
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
            }
        }
        .task { await unlock() }
    }
}
