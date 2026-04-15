import SwiftUI
import Models

/// Horizontal row of tappable vendor avatars (initials) for the active block.
///
/// Displayed below `ActiveBlockHero` on the live dashboard. Each circle shows
/// the vendor's initials and is tappable. Long-press reveals a context menu
/// with Call and Message actions backed by `tel://` and `sms://` URL schemes.
struct VendorQuickContactRow: View {

    let vendors: [VendorModel]
    let onVendorTapped: (VendorModel) -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        if !vendors.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(vendors, id: \.id) { vendor in
                        Button {
                            onVendorTapped(vendor)
                        } label: {
                            vendorAvatar(vendor)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            contextMenuItems(for: vendor)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenuItems(for vendor: VendorModel) -> some View {
        let phone = vendor.phone.trimmingCharacters(in: .whitespacesAndNewlines)

        if !phone.isEmpty, let telURL = URL(string: "tel://\(phone)") {
            Button {
                openURL(telURL)
            } label: {
                Label(String(localized: "Call"), systemImage: "phone.fill")
            }
        }

        if !phone.isEmpty, let smsURL = URL(string: "sms://\(phone)") {
            Button {
                openURL(smsURL)
            } label: {
                Label(String(localized: "Message"), systemImage: "message.fill")
            }
        }

        if phone.isEmpty {
            Text(String(localized: "No phone number"))
        }
    }

    // MARK: - Avatar

    private func vendorAvatar(_ vendor: VendorModel) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 44, height: 44)

                Text(initials(for: vendor.name))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
            }

            Text(vendor.name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: 56)
        }
    }

    // MARK: - Helpers

    private func initials(for name: String) -> String {
        let components = name.split(separator: " ")
        switch components.count {
        case 0:
            return "?"
        case 1:
            return String(components[0].prefix(1)).uppercased()
        default:
            let first = components[0].prefix(1)
            let last = components[components.count - 1].prefix(1)
            return "\(first)\(last)".uppercased()
        }
    }
}
