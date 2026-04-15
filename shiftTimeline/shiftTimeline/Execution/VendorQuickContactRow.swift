import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import Models

/// Horizontal row of vendor avatars (initials) for the active block.
///
/// Displayed below `ActiveBlockHero` on the live dashboard. Each circle shows
/// the vendor's initials. Long-press reveals a context menu with Call and
/// Message actions backed by `tel://` and `sms://` URL schemes.
struct VendorQuickContactRow: View {

    let vendors: [VendorModel]

    @Environment(\.openURL) private var openURL

    var body: some View {
        if !vendors.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(vendors, id: \.id) { vendor in
                        vendorAvatar(vendor)
                            .contextMenu {
                                contextMenuItems(for: vendor)
                            }
                            .accessibilityLabel(vendor.name)
                            .accessibilityHint(
                                normalizedPhone(vendor.phone).isEmpty
                                    ? String(localized: "No contact actions available")
                                    : String(localized: "Long press for contact options")
                            )
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenuItems(for vendor: VendorModel) -> some View {
        let digits = normalizedPhone(vendor.phone)

        if !digits.isEmpty, canOpen("tel://"), let telURL = URL(string: "tel://\(digits)") {
            Button {
                openURL(telURL)
            } label: {
                Label(String(localized: "Call"), systemImage: "phone.fill")
            }
        }

        if !digits.isEmpty, canOpen("sms:"), let smsURL = URL(string: "sms:\(digits)") {
            Button {
                openURL(smsURL)
            } label: {
                Label(String(localized: "Message"), systemImage: "message.fill")
            }
        }

        if digits.isEmpty {
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
        .accessibilityElement(children: .combine)
    }

    // MARK: - Helpers

    /// Strips formatting characters, keeping only digits and leading "+".
    private func normalizedPhone(_ raw: String) -> String {
        raw.filter { $0.isNumber || $0 == "+" }
    }

    private func canOpen(_ scheme: String) -> Bool {
        #if canImport(UIKit)
        guard let url = URL(string: scheme) else { return false }
        return UIApplication.shared.canOpenURL(url)
        #else
        return false
        #endif
    }

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
