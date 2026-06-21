import Foundation
import SwiftData
import Models
import Services
import os

/// Drives **Demo Mode** — a fully local, pre-seeded sandbox the App Review team
/// enters by signing in with the dedicated reviewer email and tapping
/// "Log in as Reviewer" on the code screen.
///
/// Demo Mode never touches the backend: it swaps in an empty in-memory
/// `ModelContainer` (the reviewer creates their own events) and bypasses
/// both the email-OTP (account) and passcode (access) layers. Because nothing
/// reaches Supabase, the reviewer email is **not a real credential** — learning
/// it only yields a throwaway local sandbox, never anyone's data.
///
/// Injected once at the scene root (`shiftTimelineApp`) and observed by
/// ``RootContainerView``, which switches to the seeded container the moment
/// ``isActive`` flips true.
@MainActor
@Observable
final class DemoSession {

    /// The lowercase email that unlocks demo mode. Compared against
    /// `EmailAuthService.normalizeEmail` output, so casing/whitespace in what the
    /// reviewer types doesn't matter.
    ///
    /// This is purely a local sentinel — demo mode never sends an OTP, creates a
    /// Supabase user, or contacts the backend for this address — so the mailbox
    /// does **not** need to exist or be able to receive mail. The domain matches
    /// the app's ToS/support domain (`shifttimeline.app`) for credibility.
    static let reviewerEmail = "reviewer@shifttimeline.app"

    /// The static code the reviewer enters on the OTP screen to drop into the
    /// local demo sandbox — provided to App Review in the submission notes.
    /// Valid *only* for ``reviewerEmail``; for every other address the real
    /// Supabase OTP flow runs unchanged.
    static let reviewerStaticCode = "123456"

    private static let logger = Logger(subsystem: "com.shift.app", category: "DemoMode")

    /// `true` once the reviewer has entered demo mode. Observed by
    /// ``RootContainerView`` to swap in the seeded local container and skip auth.
    private(set) var isActive = false

    /// The empty in-memory container backing demo mode. Built lazily on
    /// ``activate()``; `nil` until then (and only `nil` after if even a bare
    /// in-memory container couldn't be created, which would already be fatal
    /// elsewhere). Starts empty — the reviewer creates their own events.
    private(set) var container: ModelContainer?

    /// Whether `email` (normalized or not) is the reviewer address.
    func isReviewer(email: String) -> Bool {
        EmailAuthService.normalizeEmail(email) == Self.reviewerEmail
    }

    /// Builds an empty in-memory sandbox and flips into demo mode. No-op if
    /// already active. The reviewer creates their own events from here, with all
    /// Pro features unlocked (in-memory only — see `SubscriptionManager.isDemoPro`).
    func activate() {
        guard !isActive else { return }
        do {
            container = try PersistenceController.forTesting()
        } catch {
            Self.logger.error("Demo container build failed: \(error.localizedDescription, privacy: .public)")
        }
        // Unlock every Pro-gated feature for the reviewer without a purchase or
        // account. Not persisted, so it never leaks past this demo session. The
        // paywall stays reachable (Settings → View Pro Plans) so the Lifetime
        // in-app purchase can still be located and tested.
        SubscriptionManager.shared.isDemoPro = true
        isActive = true
    }
}
