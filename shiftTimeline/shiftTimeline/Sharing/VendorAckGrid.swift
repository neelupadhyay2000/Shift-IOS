import SwiftUI
import Models

/// Grid of vendor avatars showing acknowledgment status for the active event.
///
/// - Green checkmark overlay: vendor has acknowledged the latest shift.
/// - Orange clock overlay: vendor has NOT yet acknowledged.
///
/// Tapping a pending vendor presents a quick-call option. The grid re-renders
/// automatically as CloudKit syncs `hasAcknowledgedLatestShift` changes.
struct VendorAckGrid: View {

    let vendors: [VendorModel]

    @Environment(\.openURL) private var openURL

    var body: some View {
        if !vendors.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Vendor Acknowledgments"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 60), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(vendors, id: \.id) { vendor in
                        vendorCell(vendor)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Cell

    @ViewBuilder
    private func vendorCell(_ vendor: VendorModel) -> some View {
        let isPending = !vendor.hasAcknowledgedLatestShift
            && vendor.pendingShiftDelta != nil

        if isPending {
            Menu {
                callButton(for: vendor)
            } label: {
                vendorCellContent(vendor, isPending: true)
            }
            .menuStyle(.borderlessButton)
        } else {
            vendorCellContent(vendor, isPending: false)
        }
    }

    private func vendorCellContent(_ vendor: VendorModel, isPending: Bool) -> some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 48, height: 48)
                    .overlay {
                        Text(initials(for: vendor.name))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                    }

                statusBadge(isPending: isPending)
            }

            Text(vendor.name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: 64)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isPending
                ? String(localized: "\(vendor.name), pending acknowledgment",
                         comment: "Accessibility: vendor name followed by pending status")
                : String(localized: "\(vendor.name), acknowledged",
                         comment: "Accessibility: vendor name followed by acknowledged status")
        )
    }

    // MARK: - Status Badge

    private func statusBadge(isPending: Bool) -> some View {
        Image(systemName: isPending ? "clock.fill" : "checkmark.circle.fill")
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(isPending ? .orange : .green)
            .background(
                Circle()
                    .fill(.black)
                    .frame(width: 14, height: 14)
            )
    }

    // MARK: - Quick Call

    @ViewBuilder
    private func callButton(for vendor: VendorModel) -> some View {
        let digits = vendor.phone.normalizedPhoneDigits

        if !digits.isEmpty, let telURL = URL(string: "tel://\(digits)") {
            Button {
                openURL(telURL)
            } label: {
                Label(
                    String(localized: "Call \(vendor.name)",
                           comment: "Quick-call menu action for a vendor"),
                    systemImage: "phone.fill"
                )
            }
        } else {
            Text(String(localized: "No phone number on file"))
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
