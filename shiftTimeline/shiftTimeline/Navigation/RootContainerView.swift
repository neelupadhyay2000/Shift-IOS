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

    var body: some View {
        if shiftTimelineApp.isUITestMode || shiftTimelineApp.isUnitTestMode {
            RootNavigator()
        } else if !authService.hasResolvedInitialSession {
            loadingView
        } else if authService.isAuthenticated {
            RootNavigator()
        } else {
            SignInView(isDismissible: false)
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
