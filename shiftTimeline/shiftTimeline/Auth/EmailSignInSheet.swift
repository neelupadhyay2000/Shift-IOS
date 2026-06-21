import SwiftUI

/// Orchestrates the two-step email-OTP sign-in flow — the email sibling of
/// ``PhoneSignInSheet``.
///
/// Starts on ``EmailEntryView``. When the OTP is dispatched it transitions to
/// the shared ``OTPVerificationView`` carrying the normalized email. Calls
/// `onSessionEstablished` when Supabase confirms a valid session so the
/// presenting view can dismiss the sheet.
struct EmailSignInSheet: View {

    private enum Step {
        case emailEntry
        case otpVerification(email: String)
    }

    private let service: EmailAuthService
    let onSessionEstablished: () -> Void

    @Environment(DemoSession.self) private var demoSession
    @State private var step: Step = .emailEntry

    init(service: EmailAuthService, onSessionEstablished: @escaping () -> Void) {
        self.service = service
        self.onSessionEstablished = onSessionEstablished
    }

    var body: some View {
        switch step {
        case .emailEntry:
            EmailEntryView(service: service) { email in
                step = .otpVerification(email: email)
            }
        case .otpVerification(let email):
            OTPVerificationView(
                destination: email,
                headline: String(localized: "Check your email"),
                verifyToken: { token in try await verify(email: email, token: token) },
                resendCode: { try await service.resendOTP(email: email) },
                onSessionEstablished: onSessionEstablished
            )
        }
    }

    /// Verifies the entered `token`. For the App Review demo account *only*, the
    /// static code drops straight into the local demo sandbox (no Supabase call,
    /// no real account) — for every other email the normal Supabase OTP
    /// verification runs unchanged. Returning without throwing signals success,
    /// so `OTPVerificationView` invokes `onSessionEstablished`.
    @MainActor
    private func verify(email: String, token: String) async throws {
        if demoSession.isReviewer(email: email), token == DemoSession.reviewerStaticCode {
            // Smooth hand-off into the seeded app: returning success makes the
            // caller dismiss this sheet (slide-down). We defer the root swap
            // until that finishes so the dismissal and the cross-fade don't
            // overlap and look choppy — RootContainerView cross-fades on
            // `demoSession.isActive`.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                demoSession.activate()
            }
            return
        }
        _ = try await service.verifyOTP(email: email, token: token)
    }
}
