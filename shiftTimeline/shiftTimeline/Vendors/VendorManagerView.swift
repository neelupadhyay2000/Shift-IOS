#if canImport(UIKit)
import UIKit
#endif
import SwiftUI
import SwiftData
import Models
import Services

struct VendorManagerView: View {

    let eventID: UUID

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.vendorRepository) private var injectedVendorRepo
    @Query private var results: [EventModel]
    @State private var showingAddSheet = false
    @State private var showingApplyTeamSheet = false
    @State private var vendorToEdit: VendorModel?
    @State private var vendorToDelete: VendorModel?
    @State private var showDeleteConfirmation = false
    @State private var vendorToReport: VendorModel?
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
                                let roleLabel = VendorRoleLabel.display(
                                    role: vendor.role, customLabel: vendor.customRoleLabel
                                )
                                vendorRow(vendor)
                                    .proCard(padding: 14)
                                    .contentShape(Rectangle())
                                    .onTapGesture { vendorToEdit = vendor }
                                    .accessibilityLabel(
                                        blockCount > 0
                                            ? "\(vendor.name), \(roleLabel), \(blockCount) blocks"
                                            : "\(vendor.name), \(roleLabel)"
                                    )
                                    .accessibilityHint(String(localized: "Double-tap to edit"))
                                    .accessibilityAddTraits(.isButton)
                                    .contextMenu {
                                        NavigationLink {
                                            VendorNotificationSettingsView(vendor: vendor)
                                        } label: {
                                            Label(String(localized: "Notification Settings"), systemImage: "bell.badge")
                                        }
                                        Button {
                                            vendorToReport = vendor
                                        } label: {
                                            Label(String(localized: "Report a Concern"), systemImage: "exclamationmark.bubble")
                                        }
                                        Button(role: .destructive) {
                                            blockVendor(vendor)
                                        } label: {
                                            Label(String(localized: "Block Contact"), systemImage: "hand.raised")
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
                    .background { ProBackground() }
                    .accessibilityIdentifier(AccessibilityID.Vendors.vendorList)
                }
            }
        }
        .navigationTitle(String(localized: "Vendors"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(String(localized: "Add Vendor"))
                .accessibilityIdentifier(AccessibilityID.Vendors.addVendorButton)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingApplyTeamSheet = true
                } label: {
                    Image(systemName: "person.3")
                }
                .accessibilityLabel(String(localized: "Add Team"))
                .accessibilityHint(String(localized: "Adds a saved vendor team to this event"))
                .accessibilityIdentifier(AccessibilityID.VendorTeams.applyTeamButton)
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            VendorFormSheet(eventID: eventID)
        }
        .sheet(isPresented: $showingApplyTeamSheet) {
            ApplyVendorTeamSheet(eventID: eventID)
        }
        .sheet(item: $vendorToEdit) { vendor in
            VendorFormSheet(eventID: eventID, vendor: vendor)
        }
        .sheet(item: $vendorToReport) { vendor in
            ReportConcernSheet(context: String(localized: "Collaborator: \(vendor.name)"))
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
        let blockCount = assignedBlockCount(for: vendor)

        HStack(spacing: 14) {
            // Role identity reads from the SF Symbol + label, not hue (single accent).
            ShiftIconTile(systemImage: vendor.role.systemImage, size: 42)

            VStack(alignment: .leading, spacing: 5) {
                Text(vendor.name)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    ShiftChip(
                        VendorRoleLabel.display(role: vendor.role, customLabel: vendor.customRoleLabel),
                        tint: ShiftPalette.neutral
                    )

                    inviteStatusBadge(for: vendor)

                    if blockCount > 0 {
                        Text(String(localized: "\(blockCount) blocks"))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer(minLength: 4)

            contactButton(for: vendor)
        }
    }

    @ViewBuilder
    private func inviteStatusBadge(for vendor: VendorModel) -> some View {
        switch VendorInviteStatus.of(invitedAt: vendor.invitedAt, profileId: vendor.profileId?.uuidString) {
        case .accepted:
            Image(systemName: "checkmark.seal.fill")
                .font(.caption2)
                .foregroundStyle(ShiftPalette.live)
                .accessibilityLabel(String(localized: "Accepted invite"))
        case .invited:
            Image(systemName: "clock.fill")
                .font(.caption2)
                .foregroundStyle(ShiftPalette.warm)
                .accessibilityLabel(String(localized: "Invite pending"))
        case .notInvited:
            EmptyView()
        }
    }

    /// Single trailing contact action — calls the vendor when a phone number is
    /// present (and the device can dial), otherwise emails them. Hidden entirely
    /// when there's neither, so the row stays clean.
    @ViewBuilder
    private func contactButton(for vendor: VendorModel) -> some View {
        let canCall = canMakePhoneCalls && !vendor.phone.isEmpty
        let canEmail = !vendor.email.isEmpty
        if canCall || canEmail {
            Button {
                if canCall { callVendor(vendor) } else { emailVendor(vendor) }
            } label: {
                Image(systemName: canCall ? "phone.fill" : "envelope.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(canCall ? Color.white : ShiftPalette.accent)
                    .frame(width: phoneButtonSize, height: phoneButtonSize)
                    .background(
                        canCall ? AnyShapeStyle(ShiftPalette.accent) : AnyShapeStyle(ShiftPalette.soft(ShiftPalette.accent)),
                        in: Circle()
                    )
                    .accessibilityHidden(true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(canCall
                ? String(localized: "Call \(vendor.name)")
                : String(localized: "Email \(vendor.name)"))
        }
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

    private func emailVendor(_ vendor: VendorModel) {
        let address = vendor.email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty, let url = URL(string: "mailto:\(address)") else { return }
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

    /// Blocks the contact (so they can't be re-invited) and removes them from
    /// the event — the "block an abusive user" path for Guideline 1.2.
    private func blockVendor(_ vendor: VendorModel) {
        BlockedContactsStore.shared.block(phone: vendor.phone, email: vendor.email)
        deleteVendor(vendor)
    }

    private var vendorRepo: any VendorRepositing {
        injectedVendorRepo ?? SwiftDataVendorRepository(context: modelContext)
    }

    private func deleteVendor(_ vendor: VendorModel) {
        // Remove from all block assignments (nullify handled by SwiftData,
        // but explicitly clearing ensures immediate UI consistency)
        if let event {
            for block in (event.tracks ?? []).flatMap({ $0.blocks ?? [] }) {
                block.vendors?.removeAll(where: { $0.id == vendor.id })
            }
        }
        // Route through the repository so the removal reaches Supabase as an
        // event_vendors tombstone — a bare modelContext.delete never syncs,
        // leaving the removed vendor with live access to the event.
        Task {
            try? await vendorRepo.delete(vendor)
            try? await vendorRepo.save()
        }
        vendorToDelete = nil
    }
}
