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
                verifyToken: { token in _ = try await service.verifyOTP(email: email, token: token) },
                resendCode: { try await service.resendOTP(email: email) },
                onSessionEstablished: onSessionEstablished
            )
        }
    }
}
