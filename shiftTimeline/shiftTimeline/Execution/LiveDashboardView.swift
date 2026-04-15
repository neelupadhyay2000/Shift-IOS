import SwiftUI
import UIKit

/// Event-day dashboard shell with a fixed dark appearance.
struct LiveDashboardView: View {
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "Live Dashboard"))
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Color.white)

                Text(String(localized: "Current block countdown will appear here."))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.88))

                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
}

#Preview("System Light") {
    LiveDashboardView()
        .environment(\.colorScheme, .light)
}

#Preview("System Dark") {
    LiveDashboardView()
        .environment(\.colorScheme, .dark)
}
