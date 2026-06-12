import Services
import SwiftUI

/// Auth gate for the whole app.
///
/// Sign-in is mandatory: a returning user with a stored session goes straight to
/// the app, a signed-out user is blocked on a non-dismissible sign-in screen, and
/// a brief loading state covers the moment between launch and the session
/// resolving (so the sign-in screen never flashes for an already-signed-in user).
///
/// Automated test runs bypass the gate — they don't sign in and drive the app
/// directly.
struct RootContainerView: View {
    @Environment(SupabaseAuthService.self) private var authService
    @Environment(DeepLinkRouter.self) private var deepLinkRouter

    @State private var isShowingLaunchPromo = false
    @Environment(\.scenePhase) private var scenePhase

    private let appLock = AppLock.shared

    @AppStorage(AppearancePreference.defaultsKey)
    private var appearanceRawValue = AppearancePreference.system.rawValue

    var body: some View {
        content
            // One brand accent everywhere: tab selection, links, toggles, and
            // controls all inherit the icon's indigo from this single tint.
            .tint(ShiftPalette.accent)
            // User-chosen appearance (Settings → Appearance); nil = system.
            .preferredColorScheme(
                AppearancePreference(rawValue: appearanceRawValue)?.colorScheme
            )
            // Access layer: covers everything (including any open sheets) on
            // cold launch and after backgrounding while a passcode exists.
            // Unlocks only via Face ID or the app passcode; "Forgot passcode?"
            // signs out so identity is re-proven with email OTP.
            .fullScreenCover(isPresented: .init(
                get: { appLock.isLocked },
                set: { _ in }
            )) {
                AppLockScreen(appLock: appLock) {
                    Task {
                        // Delete the account's passcode record first — the
                        // session is still valid (only the UI is locked) —
                        // so the post-OTP restore can't reinstall the
                        // forgotten passcode. Then sign out to re-prove
                        // identity by email.
                        if let profileID = authService.currentProfileID {
                            let sync = PasscodeSyncService(client: SupabaseClientProvider.shared.client)
                            try? await sync.deleteRecord(profileID: profileID)
                        }
                        try? await authService.signOut()
                    }
                }
                .interactiveDismissDisabled()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { appLock.lockOnBackground() }
            }
            // Foreground shift pushes are suppressed as system notifications and
            // surfaced here as an in-app banner instead.
            .overlay(alignment: .top) { foregroundBanner }
            .animation(.spring(duration: 0.35), value: deepLinkRouter.foregroundShiftBanner)
            .fullScreenCover(isPresented: $isShowingLaunchPromo) {
                LaunchPromoView()
            }
    }

    @ViewBuilder
    private var content: some View {
        if shiftTimelineApp.isUITestMode || shiftTimelineApp.isUnitTestMode {
            RootNavigator()
        } else if !authService.hasResolvedInitialSession {
            loadingView
        } else if authService.isAuthenticated {
            if appLock.hasPasscode {
                RootNavigator()
                    .task { await maybeShowLaunchPromo() }
            } else if appLock.isRestoringRecord {
                // The account's passcode record is being fetched — hold the
                // loading view rather than flash the setup UI at a user whose
                // passcode is about to be restored.
                loadingView
            } else {
                // Genuinely no passcode for this account: first sign-up, or
                // an upgrade from a pre-passcode build.
                PasscodeSetupView()
            }
        } else {
            SignInView(isDismissible: false)
        }
    }

    /// Shows the launch promo at most once per calendar day for free users
    /// (the last-shown stamp persists across launches — see LaunchPromoSchedule).
    ///
    /// Waits briefly so the StoreKit entitlement check can resolve (a Pro user
    /// must never see it), and stands down when the launch is already routed
    /// somewhere intentional — a notification tap or an invite link mid-claim.
    private func maybeShowLaunchPromo() async {
        let defaults = UserDefaults.standard
        let lastShown = defaults.object(forKey: LaunchPromoSchedule.defaultsKey) as? Date
        guard LaunchPromoSchedule.shouldShow(lastShown: lastShown, now: .now) else { return }
        try? await Task.sleep(for: .seconds(1.5))
        guard !Task.isCancelled,
              !SubscriptionManager.shared.isProUser,
              deepLinkRouter.pendingDestination == nil,
              deepLinkRouter.pendingInviteVendorID == nil
        else { return }
        defaults.set(Date.now, forKey: LaunchPromoSchedule.defaultsKey)
        isShowingLaunchPromo = true
    }

    @ViewBuilder
    private var foregroundBanner: some View {
        if let banner = deepLinkRouter.foregroundShiftBanner {
            ForegroundShiftBannerView(
                banner: banner,
                onTap: {
                    deepLinkRouter.pendingDestination = .event(id: banner.eventID)
                    deepLinkRouter.foregroundShiftBanner = nil
                },
                onDismiss: {
                    // Only clear if this exact banner is still showing — a newer
                    // push may have replaced it while this one's timer ran.
                    if deepLinkRouter.foregroundShiftBanner?.id == banner.id {
                        deepLinkRouter.foregroundShiftBanner = nil
                    }
                }
            )
            .transition(.move(edge: .top).combined(with: .opacity))
            .zIndex(1)
        }
    }

    private var loadingView: some View {
        // Matches the sign-in brand wash so launch → loading → gate (or app)
        // reads as one continuous surface instead of a system-background flash.
        VStack(spacing: 16) {
            Image(systemName: "person.badge.shield.checkmark.fill")
                .font(.system(size: 56))
                .foregroundStyle(.white.opacity(0.9))
                .symbolRenderingMode(.hierarchical)
            ProgressView()
                .tint(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { SignInBrandBackground() }
    }
}
