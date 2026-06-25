import Foundation

/// Which credential the account uses to prove identity via OTP.
///
/// Persisted across sign-outs so recovery flows (notably forgot-passcode, which
/// signs out to re-prove identity) can route the user straight back to the
/// method they actually use — phone users to the phone screen, email users to
/// the email screen — instead of a generic chooser.
enum AuthMethod: String, Sendable {
    case email
    case phone

    /// User-facing name of the code's delivery channel, for method-aware copy
    /// (e.g. "You'll sign in again with an email code / a text-message code").
    var codeChannelDescription: String {
        switch self {
        case .email: String(localized: "email code")
        case .phone: String(localized: "text-message code")
        }
    }
}

/// The last account that established a session on this device — method and
/// display name. Survives sign-out (UserDefaults) so recovery / re-auth can
/// pre-route to the right method and greet a returning user by name. Cleared on
/// account deletion (see `SupabaseAuthService.deleteAccount`).
enum AuthMethodStore {
    private static let methodKey = "auth.lastMethod"
    private static let nameKey = "auth.lastDisplayName"

    static var last: AuthMethod? {
        get { UserDefaults.standard.string(forKey: methodKey).flatMap(AuthMethod.init) }
        set { UserDefaults.standard.set(newValue?.rawValue, forKey: methodKey) }
    }

    /// The signed-in user's display name, cached for the "Welcome back, <name>"
    /// landing shown to a signed-out returning user before they re-authenticate.
    static var lastDisplayName: String? {
        get { UserDefaults.standard.string(forKey: nameKey) }
        set { UserDefaults.standard.set(newValue, forKey: nameKey) }
    }

    /// Forget the remembered account (account deletion) — no stale name/method
    /// should greet the next person who signs in on this device.
    static func clear() {
        UserDefaults.standard.removeObject(forKey: methodKey)
        UserDefaults.standard.removeObject(forKey: nameKey)
    }
}
