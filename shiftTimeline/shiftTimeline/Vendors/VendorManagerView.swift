#if canImport(UIKit)
import UIKit
#endif
import SwiftUI
import SwiftData
import Models

struct VendorManagerView: View {

    let eventID: UUID

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query private var results: [EventModel]
    @State private var showingAddSheet = false
    @State private var vendorToEdit: VendorModel?
    @State private var vendorToDelete: VendorModel?
    @State private var showDeleteConfirmation = false
    @ScaledMetric private var phoneButtonSize: CGFloat = 38

    private var event: EventModel? { results.first }

    init(eventID: UUID) {
        self.eventID = eventID
        _results = Query(
            filter: #Predicate<EventModel> { $0.id == eventID }
        )
    }

    var body: some View {
        Group {
            if let event {
                if (event.vendors ?? []).isEmpty {
                    ContentUnavailableView(
                        String(localized: "No Vendors"),
                        systemImage: "person.2.slash",
                        description: Text(String(localized: "Tap + to add a vendor."))
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach((event.vendors ?? []).sorted(by: { $0.name < $1.name })) { vendor in
                                let blockCount = assignedBlockCount(for: vendor)
                                vendorRow(vendor)
                                    .premiumCard(padding: 12)
                                    .contentShape(Rectangle())
                                    .onTapGesture { vendorToEdit = vendor }
                                    .accessibilityLabel(
                                        blockCount > 0
                                            ? "\(vendor.name), \(vendor.role.displayName), \(blockCount) blocks"
                                            : "\(vendor.name), \(vendor.role.displayName)"
                                    )
                                    .accessibilityHint(String(localized: "Double-tap to edit"))
                                    .accessibilityAddTraits(.isButton)
                                    .scrollFade()
                                    .contextMenu {
                                        NavigationLink {
                                            VendorNotificationSettingsView(vendor: vendor)
                                        } label: {
                                            Label(String(localized: "Notification Settings"), systemImage: "bell.badge")
                                        }
                                        Button(role: .destructive) {
                                            requestDelete(vendor)
                                        } label: {
                                            Label(String(localized: "Delete"), systemImage: "trash")
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .background { WarmBackground() }
                }
            }
        }
        .navigationTitle(String(localized: "Vendors"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(String(localized: "Add Vendor"))
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            VendorFormSheet(eventID: eventID)
        }
        .sheet(item: $vendorToEdit) { vendor in
            VendorFormSheet(eventID: eventID, vendor: vendor)
        }
        .alert(
            String(localized: "Delete Vendor"),
            isPresented: $showDeleteConfirmation,
            presenting: vendorToDelete
        ) { vendor in
            Button(String(localized: "Cancel"), role: .cancel) {
                vendorToDelete = nil
            }
            Button(String(localized: "Delete"), role: .destructive) {
                deleteVendor(vendor)
            }
        } message: { vendor in
            let count = assignedBlockCount(for: vendor)
            if count > 0 {
                Text(String(localized: "\"\(vendor.name)\" is assigned to \(count) block(s). Deleting will remove them from all assignments."))
            } else {
                Text(String(localized: "Are you sure you want to delete \"\(vendor.name)\"?"))
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func vendorRow(_ vendor: VendorModel) -> some View {
        let roleColor = ShiftDesign.roleColor(for: vendor.role)
        let blockCount = assignedBlockCount(for: vendor)

        HStack(spacing: 14) {
            // Role icon — decorative; role is conveyed via the text badge below
            Image(systemName: vendor.role.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(roleColor.gradient, in: RoundedRectangle(cornerRadius: ShiftDesign.iconRadius, style: .continuous))
                .symbolEffect(.bounce, value: vendor.id)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(vendor.name)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(vendor.role.displayName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(roleColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(roleColor)

                    if blockCount > 0 {
                        Text("\(blockCount) blocks")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer(minLength: 4)

            // Contact info
            VStack(alignment: .trailing, spacing: 3) {
                if !vendor.phone.isEmpty {
                    Label(vendor.phone, systemImage: "phone.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !vendor.email.isEmpty {
                    Label(vendor.email, systemImage: "envelope.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)

            phoneButton(for: vendor)
        }
    }

    @ViewBuilder
    private func phoneButton(for vendor: VendorModel) -> some View {
        let canCall = canMakePhoneCalls && !vendor.phone.isEmpty
        let roleColor = ShiftDesign.roleColor(for: vendor.role)
        Button {
            callVendor(vendor)
        } label: {
            Image(systemName: "phone.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(canCall ? roleColor : .gray)
                .frame(width: phoneButtonSize, height: phoneButtonSize)
                .background(
                    canCall ? roleColor.opacity(0.12) : Color.gray.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .disabled(!canCall)
        .accessibilityLabel(canCall
            ? String(localized: "Call \(vendor.name)")
            : String(localized: "Call unavailable"))
        .accessibilityHint(canCall ? "" : String(localized: "No phone number on file or device cannot make calls"))
    }

    private var canMakePhoneCalls: Bool {
        #if canImport(UIKit)
        guard let url = URL(string: "tel://") else { return false }
        return UIApplication.shared.canOpenURL(url)
        #else
        return false
        #endif
    }

    private func callVendor(_ vendor: VendorModel) {
        let digits = vendor.phone.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty, let url = URL(string: "tel://\(digits)") else { return }
        openURL(url)
    }

    // MARK: - Actions

    private func assignedBlockCount(for vendor: VendorModel) -> Int {
        guard let event else { return 0 }
        return (event.tracks ?? [])
            .flatMap { $0.blocks ?? [] }
            .filter { ($0.vendors ?? []).contains(where: { $0.id == vendor.id }) }
            .count
    }

    private func requestDelete(_ vendor: VendorModel) {
        vendorToDelete = vendor
        showDeleteConfirmation = true
    }

    private func deleteVendor(_ vendor: VendorModel) {
        // Remove from all block assignments (nullify handled by SwiftData,
        // but explicitly clearing ensures immediate UI consistency)
        if let event {
            for block in (event.tracks ?? []).flatMap({ $0.blocks ?? [] }) {
                block.vendors?.removeAll(where: { $0.id == vendor.id })
            }
        }
        modelContext.delete(vendor)
        vendorToDelete = nil
    }
}
