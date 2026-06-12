import Supabase
import SwiftUI

// MARK: - Brand palette

/// Brand-splash colors sampled from the app icon — scoped to sign-in, the one
/// fixed-dark "brand moment" in the app. Deliberately not in `ShiftPalette`,
/// whose accent rules forbid decorative washes on the working surfaces.
private enum SignInPalette {
    static let indigoTop = Color(red: 0.33, green: 0.27, blue: 0.72)
    static let indigoBottom = Color(red: 0.13, green: 0.10, blue: 0.32)
    static let mint = Color(red: 0.24, green: 0.87, blue: 0.73)
    static let ink = Color(red: 0.06, green: 0.09, blue: 0.13)
    /// The icon's timeline-block colors, left to right.
    static let blocks: [Color] = [
        Color(red: 0.96, green: 0.47, blue: 0.20),
        Color(red: 0.22, green: 0.73, blue: 0.86),
        Color(red: 0.78, green: 0.27, blue: 0.86),
        Color(red: 0.97, green: 0.70, blue: 0.21),
        Color(red: 0.36, green: 0.83, blue: 0.44),
    ]
}

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

    init(isDismissible: Bool = true) {
        self.isDismissible = isDismissible
    }

    var body: some View {
        NavigationStack {
            ZStack {
                brandBackground
                VStack(spacing: 40) {
                    Spacer()
                    header
                    Spacer()
                    signInButtons
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

    // MARK: - Background

    /// Deep indigo wash from the icon, with a soft glow rising behind the motif.
    private var brandBackground: some View {
        LinearGradient(
            colors: [SignInPalette.indigoTop, SignInPalette.indigoBottom],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay {
            RadialGradient(
                colors: [.white.opacity(0.10), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 340
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 32) {
            TimelineMotif()
                .accessibilityHidden(true)
            VStack(spacing: 8) {
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

    // MARK: - Buttons

    private var signInButtons: some View {
        VStack(spacing: 12) {
            // Email OTP is the primary sign-in (Apple removed) — always available.
            emailButton
            // Phone OTP is gated off until an SMS provider is configured
            // (FeatureFlags.phoneSignIn) — see PhoneAuthService / Supabase Auth.
            if FeatureFlags.phoneSignIn {
                phoneButton
            }
        }
    }

    private var emailButton: some View {
        Button {
            isShowingEmailSignIn = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "envelope.fill")
                Text(String(localized: "Sign in with Email"))
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(SignInPalette.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                SignInPalette.mint,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Sign in with Email"))
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
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                .white.opacity(0.14),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Sign in with Phone"))
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
