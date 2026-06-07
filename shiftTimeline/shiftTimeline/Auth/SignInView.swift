import Supabase
import SwiftUI

/// Unified sign-in sheet presenting Sign in with Apple and Phone OTP.
///
/// Present this modally whenever a sharing or sync feature requires auth.
/// Both sign-in paths call `dismiss()` on completion so the caller only
/// needs to observe `SupabaseAuthService.isAuthenticated` for reactive updates.
struct SignInView: View {
    @Environment(SupabaseAuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss

    /// When `false`, the Cancel button is hidden — used by the launch auth gate,
    /// where sign-in is mandatory and there's nothing to dismiss back to.
    let isDismissible: Bool

    @State private var isShowingPhoneSignIn = false
    @State private var isAppleSignInInProgress = false
    @State private var errorMessage: String?

    init(isDismissible: Bool = true) {
        self.isDismissible = isDismissible
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 40) {
                Spacer()
                header
                Spacer()
                signInButtons
                Spacer()
            }
            .padding(.horizontal, 28)
            .navigationTitle(String(localized: "Sign In"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isDismissible {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Cancel")) { dismiss() }
                            .tint(.secondary)
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingPhoneSignIn) {
            PhoneSignInSheet(
                service: PhoneAuthService(client: SupabaseClientProvider.shared.client),
                onSessionEstablished: {
                    isShowingPhoneSignIn = false
                    dismiss()
                }
            )
        }
        .alert(String(localized: "Sign In Failed"), isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            if let msg = errorMessage { Text(msg) }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.badge.shield.checkmark.fill")
                .font(.system(size: 60))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text(String(localized: "Sign in to SHIFT"))
                    .font(.title2.bold())
                Text(String(localized: "Share your timeline with vendors and collaborate in real time."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Buttons

    private var signInButtons: some View {
        VStack(spacing: 12) {
            appleButton
            // Phone OTP is gated off until an SMS provider is configured
            // (FeatureFlags.phoneSignIn) — see PhoneAuthService / Supabase Auth.
            if FeatureFlags.phoneSignIn {
                phoneButton
            }
        }
    }

    private var appleButton: some View {
        Button {
            Task { await signInWithApple() }
        } label: {
            HStack(spacing: 8) {
                if isAppleSignInInProgress {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color(uiColor: .systemBackground))
                } else {
                    Image(systemName: "apple.logo")
                }
                Text(String(localized: "Sign in with Apple"))
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(Color(uiColor: .systemBackground))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Color.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isAppleSignInInProgress)
        .accessibilityLabel(String(localized: "Sign in with Apple"))
    }

    private var phoneButton: some View {
        Button {
            isShowingPhoneSignIn = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "phone.fill")
                Text(String(localized: "Sign in with Phone"))
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                Color(uiColor: .secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Sign in with Phone"))
    }

    // MARK: - Apple sign-in action

    private func signInWithApple() async {
        isAppleSignInInProgress = true
        defer { isAppleSignInInProgress = false }
        let service = AppleSignInService(client: SupabaseClientProvider.shared.client)
        do {
            let result = try await service.signIn()
            if result.isNewUser {
                await authService.upsertProfile(from: result.session.user, displayName: result.displayName)
            }
            dismiss()
        } catch AppleSignInError.cancelled {
            // User dismissed the Apple sheet — no error to surface
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Preview

#Preview("Sign In") {
    SignInView()
        .environment(SupabaseAuthService())
}
