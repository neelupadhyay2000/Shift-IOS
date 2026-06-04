import SwiftUI

/// Orchestrates the two-step phone-OTP sign-in flow.
///
/// Starts on `PhoneNumberEntryView`. When the OTP is dispatched it
/// transitions to `OTPVerificationView` carrying the normalized phone number.
/// Calls `onSessionEstablished` when Supabase confirms a valid session so the
/// presenting view can dismiss the sheet.
struct PhoneSignInSheet: View {

    private enum Step {
        case phoneEntry
        case otpVerification(phone: String)
    }

    private let service: PhoneAuthService
    let onSessionEstablished: () -> Void

    @State private var step: Step = .phoneEntry

    init(service: PhoneAuthService, onSessionEstablished: @escaping () -> Void) {
        self.service = service
        self.onSessionEstablished = onSessionEstablished
    }

    var body: some View {
        switch step {
        case .phoneEntry:
            PhoneNumberEntryView(service: service) { phone in
                step = .otpVerification(phone: phone)
            }
        case .otpVerification(let phone):
            OTPVerificationView(
                service: service,
                phone: phone,
                onSessionEstablished: onSessionEstablished
            )
        }
    }
}
