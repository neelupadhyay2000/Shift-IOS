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

    var body: some View {
        content
            // Foreground shift pushes are suppressed as system notifications and
            // surfaced here as an in-app banner instead (SHIFT-648).
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
            RootNavigator()
                .task { await maybeShowLaunchPromo() }
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
        VStack(spacing: 16) {
            Image(systemName: "person.badge.shield.checkmark.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
            ProgressView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }
}
