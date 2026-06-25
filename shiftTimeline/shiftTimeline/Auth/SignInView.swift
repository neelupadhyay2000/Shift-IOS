import Supabase
import SwiftUI

/// Unified sign-in sheet presenting Email OTP (primary) and Phone OTP (gated).
///
/// Present this modally whenever a sharing or sync feature requires auth.
/// Each sign-in path calls `dismiss()` on completion so the caller only
/// needs to observe `SupabaseAuthService.isAuthenticated` for reactive updates.
struct SignInView: View {
    @Environment(\.dismiss) private var dismiss

    /// When `false`, the Cancel button is hidden — used by the launch auth gate,
    /// where sign-in is mandatory and there's nothing to dismiss back to.
    let isDismissible: Bool

    @State private var isShowingPhoneSignIn = false
    @State private var isShowingEmailSignIn = false
    @State private var errorMessage: String?

    /// Set when a remembered user taps "Use a different account" — reveals the
    /// full method chooser instead of the personalized "Welcome back" landing.
    @State private var showChooser = false

    init(isDismissible: Bool = true) {
        self.isDismissible = isDismissible
    }

    /// The remembered account's method, but only if that method is currently
    /// available (phone is gated). `nil` → no usable remembered account.
    private var rememberedMethod: AuthMethod? {
        switch AuthMethodStore.last {
        case .some(.email) where FeatureFlags.emailSignIn: .email
        case .some(.phone) where FeatureFlags.phoneSignIn: .phone
        default: nil
        }
    }

    /// Show the personalized "Welcome back, <name>" landing when we have a
    /// usable remembered method and a cached name, and the user hasn't asked
    /// for the full chooser.
    private var personalizedName: String? {
        guard !showChooser, rememberedMethod != nil else { return nil }
        guard let name = AuthMethodStore.lastDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return nil }
        return name
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SignInBrandBackground()
                VStack(spacing: 40) {
                    Spacer()
                    header
                    Spacer()
                    actions
                    Spacer()
                }
                .padding(.horizontal, 28)
            }
            .navigationTitle(String(localized: "Sign In"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                if isDismissible {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Cancel")) { dismiss() }
                            .tint(.white.opacity(0.8))
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $isShowingPhoneSignIn) {
            PhoneSignInSheet(
                service: PhoneAuthService(client: SupabaseClientProvider.shared.client),
                onSessionEstablished: {
                    isShowingPhoneSignIn = false
                    dismiss()
                }
            )
        }
        .sheet(isPresented: $isShowingEmailSignIn) {
            EmailSignInSheet(
                service: EmailAuthService(client: SupabaseClientProvider.shared.client),
                onSessionEstablished: {
                    isShowingEmailSignIn = false
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
        VStack(spacing: 32) {
            TimelineMotif()
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                if let name = personalizedName {
                    Text(String(localized: "Welcome back,"))
                        .font(.title2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                    Text(name)
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                } else {
                    Text(String(localized: "Welcome to SHIFT"))
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                    Text(String(localized: "Share your timeline with vendors and collaborate in real time."))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    // MARK: - Actions

    /// A returning user (remembered method + name) gets a one-tap "Continue"
    /// to their own method plus an escape hatch to the full chooser; everyone
    /// else gets the method chooser. OTP has no password, so one tap both
    /// creates the account and logs in — there's no separate sign-up / log-in.
    @ViewBuilder
    private var actions: some View {
        if let name = personalizedName, let method = rememberedMethod {
            VStack(spacing: 12) {
                continueButton(for: method)
                    .accessibilityLabel(String(localized: "Continue as \(name)"))
                Button(String(localized: "Use a different account")) {
                    showChooser = true
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.top, 4)
            }
        } else {
            chooserButtons
        }
    }

    private var chooserButtons: some View {
        VStack(spacing: 12) {
            emailButton
            // Phone OTP is gated off until an SMS provider is configured
            // (FeatureFlags.phoneSignIn) — see PhoneAuthService / Supabase Auth.
            if FeatureFlags.phoneSignIn {
                phoneButton
            }
            Text(String(localized: "New or returning — we'll send you a one-time code."))
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func continueButton(for method: AuthMethod) -> some View {
        switch method {
        case .email: emailButton
        case .phone:
            Button { isShowingPhoneSignIn = true } label: {
                Label(String(localized: "Continue with Phone"), systemImage: "phone.fill")
            }
            .buttonStyle(SignInPrimaryButtonStyle())
        }
    }

    private var emailButton: some View {
        Button {
            isShowingEmailSignIn = true
        } label: {
            Label(String(localized: "Continue with Email"), systemImage: "envelope.fill")
        }
        .buttonStyle(SignInPrimaryButtonStyle())
        .accessibilityLabel(String(localized: "Continue with Email"))
    }

    private var phoneButton: some View {
        Button {
            isShowingPhoneSignIn = true
        } label: {
            Label(String(localized: "Continue with Phone"), systemImage: "phone.fill")
        }
        .buttonStyle(SignInSecondaryButtonStyle())
        .accessibilityLabel(String(localized: "Continue with Phone"))
    }
}

// MARK: - Timeline motif

/// The app icon's staggered timeline blocks with the glowing bar threading
/// through them, recreated in vector so it stays crisp at any size. Purely
/// decorative — always paired with `accessibilityHidden(true)`.
private struct TimelineMotif: View {
    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(SignInPalette.blocks.enumerated()), id: \.offset) { index, color in
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(color.gradient)
                    .frame(width: 36, height: index.isMultiple(of: 2) ? 62 : 82)
                    .offset(y: index.isMultiple(of: 2) ? -9 : 9)
                    .shadow(color: color.opacity(0.5), radius: 10, y: 2)
            }
        }
        .overlay {
            Capsule()
                .fill(.white.opacity(0.92))
                .frame(height: 6)
                .padding(.horizontal, -12)
                .shadow(color: .white.opacity(0.7), radius: 7)
        }
        .frame(height: 112)
    }
}

// MARK: - Preview

#Preview("Sign In") {
    SignInView()
        .environment(SupabaseAuthService())
}
