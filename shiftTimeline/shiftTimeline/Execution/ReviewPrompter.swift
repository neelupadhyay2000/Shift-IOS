import Foundation

/// Once-per-app-version gate around the App Store review request.
///
/// Fired at the moment of peak goodwill — right after a user completes running
/// a real event. Apple already rate-limits `requestReview` to ~3 prompts a
/// year; this gate additionally guarantees we never ask twice on the same
/// version, so the prompt stays rare and well-timed.
enum ReviewPrompter {

    static let defaultsKey = "lastReviewPromptVersion"

    /// True when a review should be requested for `currentVersion`.
    nonisolated static func shouldRequest(lastPromptedVersion: String?, currentVersion: String) -> Bool {
        lastPromptedVersion != currentVersion
    }

    /// Stamps the current version and invokes `action` if this version hasn't
    /// prompted yet. The stamp is written before the request so a crash or
    /// system suppression can't cause a re-ask loop.
    @MainActor
    static func requestIfNeeded(defaults: UserDefaults = .standard, action: () -> Void) {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        guard shouldRequest(
            lastPromptedVersion: defaults.string(forKey: defaultsKey),
            currentVersion: currentVersion
        ) else { return }
        defaults.set(currentVersion, forKey: defaultsKey)
        action()
    }
}
