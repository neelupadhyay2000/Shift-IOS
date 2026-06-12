import SwiftUI

/// Second step of an OTP sign-in flow — channel-agnostic (phone or email).
///
/// Accepts a 6-digit code sent to `destination`, verifies it via the injected
/// `verifyToken` closure, and calls `onSessionEstablished` on success.
/// `SupabaseAuthService` is updated automatically via its `authStateChanges`
/// listener — this callback is purely for navigation.
///
/// Resend is gated behind a 60-second cooldown that starts when the view appears
/// and resets each time a new code is dispatched.
struct OTPVerificationView: View {

    /// What the code was sent to (E.164 phone or email), shown in the header.
    let destination: String
    /// Channel-specific headline, e.g. "Check your messages" / "Check your email".
    let headline: String
    /// Verifies the entered code with Supabase; throws on failure.
    let verifyToken: @MainActor (String) async throws -> Void
    /// Re-sends a fresh code to `destination`.
    let resendCode: @MainActor () async throws -> Void
    /// Called when Supabase returns a valid session. Use this to dismiss
    /// or advance the navigation stack.
    let onSessionEstablished: () -> Void

    @Environment(\.dismiss) private var dismiss

    init(
        destination: String,
        headline: String,
        verifyToken: @escaping @MainActor (String) async throws -> Void,
        resendCode: @escaping @MainActor () async throws -> Void,
        onSessionEstablished: @escaping () -> Void
    ) {
        self.destination = destination
        self.headline = headline
        self.verifyToken = verifyToken
        self.resendCode = resendCode
        self.onSessionEstablished = onSessionEstablished
    }

    /// Returns `true` when `token` is exactly 6 decimal digits.
    private static func isValidToken(_ token: String) -> Bool {
        token.count == 6 && token.allSatisfy(\.isNumber)
    }

    @State private var token = ""
    @State private var isVerifying = false
    @State private var isResending = false
    @State private var resendSecondsRemaining = 0
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    private static let resendCooldownSeconds = 60

    // MARK: - Derived state

    private var canVerify: Bool {
        Self.isValidToken(token) && !isVerifying
    }

    private var canResend: Bool {
        resendSecondsRemaining == 0 && !isResending && !isVerifying
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                SignInBrandBackground()
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.top, 24)
                        .padding(.bottom, 32)

                    codeField
                        .padding(.bottom, 20)

                    verifyButton
                        .padding(.bottom, 32)

                    resendSection

                    Spacer()
                }
                .padding(.horizontal, 24)
            }
            .navigationTitle(String(localized: "Enter Code"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                        .tint(.white.opacity(0.8))
                }
            }
            .onAppear {
                startCooldown()
            }
            .onChange(of: token) { _, newValue in
                // Enforce 6-character limit and trigger auto-verification.
                if newValue.count > 6 {
                    token = String(newValue.prefix(6))
                } else if newValue.count == 6 && canVerify {
                    Task { await verify() }
                }
            }
            .alert(String(localized: "Verification Failed"), isPresented: $showErrorAlert) {
                Button(String(localized: "OK"), role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            SignInStepBadge(systemImage: "key.fill")
            VStack(alignment: .leading, spacing: 6) {
                Text(headline)
                    .font(.title.bold())
                    .foregroundStyle(.white)
                Text(
                    String(
                        localized: "Enter the 6-digit code sent to \(destination).",
                        comment: "Subtitle on OTP entry screen. %@ is the phone number or email."
                    )
                )
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
            }
        }
    }

    private var codeField: some View {
        TextField(String(localized: "000000"), text: $token)
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .multilineTextAlignment(.center)
            .font(.system(size: 36, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .tint(SignInPalette.mint)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .signInFieldBackground()
    }

    private var verifyButton: some View {
        Button {
            Task { await verify() }
        } label: {
            if isVerifying {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(SignInPalette.ink)
                    Text(String(localized: "Verifying…"))
                }
            } else {
                Text(String(localized: "Verify Code"))
            }
        }
        .buttonStyle(SignInPrimaryButtonStyle())
        .disabled(!canVerify)
    }

    private var resendSection: some View {
        HStack {
            Spacer()
            if resendSecondsRemaining > 0 {
                Text(
                    String(
                        localized: "Resend in \(resendSecondsRemaining)s",
                        comment: "Countdown label before the user can resend the OTP."
                    )
                )
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
            } else {
                Button {
                    Task { await resend() }
                } label: {
                    if isResending {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(SignInPalette.mint)
                            Text(String(localized: "Sending…"))
                        }
                    } else {
                        Text(String(localized: "Resend Code"))
                    }
                }
                .font(.subheadline.weight(.medium))
                .tint(SignInPalette.mint)
                .disabled(!canResend)
            }
            Spacer()
        }
    }

    // MARK: - Actions

    private func verify() async {
        isVerifying = true
        defer { isVerifying = false }
        do {
            try await verifyToken(token)
            onSessionEstablished()
        } catch {
            token = ""
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }

    private func resend() async {
        isResending = true
        defer { isResending = false }
        do {
            try await resendCode()
            token = ""
            startCooldown()
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }

    /// Starts (or restarts) the 60-second resend cooldown.
    ///
    /// The task runs on the MainActor so it can safely decrement the
    /// `@State` property without crossing actor boundaries.
    private func startCooldown() {
        resendSecondsRemaining = Self.resendCooldownSeconds
        Task { @MainActor in
            for remaining in stride(
                from: Self.resendCooldownSeconds - 1,
                through: 0,
                by: -1
            ) {
                try? await Task.sleep(for: .seconds(1))
                resendSecondsRemaining = remaining
            }
        }
    }
}

// MARK: - Preview

#Preview {
    OTPVerificationView(
        destination: "+15551234567",
        headline: String(localized: "Check your messages"),
        verifyToken: { _ in },
        resendCode: { },
        onSessionEstablished: {
            print("Session established")
        }
    )
}
