import SwiftUI

/// Small green pill marking something as assigned to the current (vendor) viewer.
/// Shared by the timeline rows and the live dashboard so the "this is yours"
/// cue looks identical everywhere a vendor sees their blocks.
struct AssignedToYouBadge: View {
    var text: String = String(localized: "Assigned to you")

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "person.fill.checkmark")
                .font(.system(size: 8, weight: .bold))
            Text(text)
                .font(.caption2)
                .fontWeight(.bold)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.green.opacity(0.15), in: Capsule())
        .foregroundStyle(.green)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(localized: "Assigned to you")))
    }
}

#Preview {
    VStack(spacing: 12) {
        AssignedToYouBadge()
        AssignedToYouBadge(text: String(localized: "Assigned"))
    }
    .padding()
}
