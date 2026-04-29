import SwiftUI
import Services

// MARK: - Trigger

enum PaywallTrigger: String, Identifiable, Sendable {
    case eventLimit
    case blockLimit
    case vendorSharing
    case liveActivity
    case pdfExport
    case templates
    case widgets

    var id: String { rawValue }

    var message: LocalizedStringKey {
        switch self {
        case .eventLimit:
            "Free plan is limited to 1 active event. Upgrade to Pro for unlimited events."
        case .blockLimit:
            "Free plan is limited to 15 blocks per event. Upgrade to Pro for unlimited blocks."
        case .vendorSharing:
            "Vendor sharing is a Pro feature. Upgrade to collaborate with your team."
        case .liveActivity:
            "Live Activities and Widgets are Pro features. Upgrade to unlock the full experience."
        case .pdfExport:
            "PDF export is a Pro feature. Upgrade to generate professional timelines."
        case .templates:
            "All templates are available on the Pro plan. Upgrade to access the full library."
        case .widgets:
            "Widgets are a Pro feature. Upgrade to see your timeline from your Home Screen."
        }
    }
}

// MARK: - View (placeholder — full implementation in ST4)

struct PaywallView: View {

    let trigger: PaywallTrigger

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Unlock SHIFT Pro", systemImage: "lock.open.fill")
            } description: {
                Text(trigger.message)
            } actions: {
                Button("View Plans") {
                    // ST4: full purchase flow wired here
                }
                .buttonStyle(.borderedProminent)

                Button("Dismiss", role: .cancel) {
                    dismiss()
                }
            }
            .navigationTitle("SHIFT Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Event Limit") { PaywallView(trigger: .eventLimit) }
#Preview("Block Limit") { PaywallView(trigger: .blockLimit) }
#Preview("Vendor Sharing") { PaywallView(trigger: .vendorSharing) }
#Preview("Live Activity") { PaywallView(trigger: .liveActivity) }
