import Foundation
import Services

/// Resolves the APNs environment the device registers against.
///
/// Token-based (.p8) APNs auth works for both environments; the value only tells
/// the server which APNs host to target and mirrors the `aps-environment`
/// entitlement Xcode emits per build configuration: Debug → sandbox, Release
/// (TestFlight / App Store) → prod. Stored verbatim in `device_tokens.environment`.
enum APNsEnvironment {
    static let sandbox = "sandbox"
    static let prod = "prod"

    static var current: String {
        #if DEBUG
        sandbox
        #else
        prod
        #endif
    }
}

/// Coordinates APNs token registration into `device_tokens` (SHIFT-642).
///
/// The two inputs arrive independently and in either order: the APNs token from
/// `AppDelegate`'s `didRegisterForRemoteNotifications`, and the signed-in profile
/// from `SupabaseAuthService`. This caches both and registers only once both are
/// known, de-duplicating so an identical (token, profile, environment) is never
/// re-sent. State changes that matter — a refreshed APNs token, or an account
/// switch on the same device — re-register; a sign-out clears the dedupe so the
/// next sign-in re-registers.
///
/// `profile_id` is never sent: the `upsert_device_token` RPC derives it from the
/// authenticated session. The cached `currentProfileID` is used only to gate
/// registration (must be signed in) and to detect account switches.
@MainActor
final class DeviceTokenRegistrar {
    static let shared = DeviceTokenRegistrar()

    private var writer: (any DeviceTokenWriting)?
    private let environment: String
    private var latestToken: String?
    private var currentProfileID: UUID?
    private var lastRegistered: Registration?

    private struct Registration: Equatable {
        let token: String
        let profileID: UUID
        let environment: String
    }

    /// Parameterless for the production singleton — wire the writer later via
    /// `configure(writer:)`. The DI init is for tests / previews.
    init(
        writer: (any DeviceTokenWriting)? = nil,
        environment: String = APNsEnvironment.current
    ) {
        self.writer = writer
        self.environment = environment
    }

    /// Supplies the Supabase-backed writer once the client exists, then attempts
    /// registration in case the token + profile already arrived.
    func configure(writer: any DeviceTokenWriting) async {
        self.writer = writer
        await register()
    }

    /// Records the raw APNs device token (from `didRegisterForRemoteNotifications`)
    /// and registers if a profile is present.
    func updateAPNsToken(_ tokenData: Data) async {
        latestToken = Self.hexString(from: tokenData)
        await register()
    }

    /// Records the signed-in profile (or `nil` on sign-out) and registers if a
    /// token is present. Sign-out clears the dedupe so the next sign-in re-registers.
    func updateProfile(_ profileID: UUID?) async {
        currentProfileID = profileID
        if profileID == nil { lastRegistered = nil }
        await register()
    }

    /// Lowercase hex encoding of the APNs token, the form `device_tokens.apns_token`
    /// stores and APNs expects.
    static func hexString(from data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private func register() async {
        guard let writer, let token = latestToken, let profileID = currentProfileID else { return }
        let candidate = Registration(token: token, profileID: profileID, environment: environment)
        guard candidate != lastRegistered else { return }

        // Optimistic set collapses concurrent triggers (token + profile arriving
        // close together) into a single write; rolled back on failure to retry.
        let previous = lastRegistered
        lastRegistered = candidate
        do {
            try await writer.upsert(apnsToken: token, environment: environment)
            SyncDiagnosticsCenter.shared.record(
                .push, "deviceTokenRegistered",
                params: ["environment": environment]
            )
        } catch {
            if lastRegistered == candidate { lastRegistered = previous }
            SyncDiagnosticsCenter.shared.record(
                .push, "deviceTokenRegisterFailed",
                params: ["error": String(describing: error)],
                severity: .error
            )
        }
    }
}
