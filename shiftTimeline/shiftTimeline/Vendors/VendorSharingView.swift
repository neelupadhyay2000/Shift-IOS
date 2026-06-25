#if canImport(UIKit)
import UIKit
#endif
import SwiftUI
import SwiftData
import Models
import Services

/// Per-vendor sharing screen: invite the vendors you've added (locked to their
/// exact phone/email) and see who has accepted. Replaces the old open
/// `UICloudSharingController` flow where anyone with the link could join.
struct VendorSharingView: View {

    let eventID: UUID

    @Query private var results: [EventModel]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.vendorRepository) private var injectedVendorRepo
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var pendingInvite: PendingInvite?
    @State private var infoMessage: String?

    private var event: EventModel? { results.first }

    /// Repository used to stamp invite state. Falls back to a SwiftData-backed
    /// instance when no provider is injected (matches the other write sites).
    private var vendorRepo: any VendorRepositing {
        injectedVendorRepo ?? SwiftDataVendorRepository(context: modelContext)
    }

    init(eventID: UUID) {
        self.eventID = eventID
        _results = Query(filter: #Predicate<EventModel> { $0.id == eventID })
    }

    var body: some View {
        List {
            Section {
                ForEach((event?.vendors ?? []).sorted(by: { $0.name < $1.name })) { vendor in
                    vendorRow(vendor)
                }
                if (event?.vendors ?? []).isEmpty {
                    Text(String(localized: "Add vendors first, then invite them here."))
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text(String(localized: "Only vendors you've added can be invited, and each invite is locked to that vendor's phone or email — only someone signing in with that phone or email can accept."))
            }
        }
        .navigationTitle(String(localized: "Invite Vendors"))
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isWorking { ProgressView().controlSize(.large) }
        }
        .sheet(item: $pendingInvite) { invite in
            composer(for: invite)
        }
        .alert(String(localized: "Couldn't Invite"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            if let errorMessage { Text(errorMessage) }
        }
        .alert(String(localized: "Invite Link Copied"), isPresented: Binding(
            get: { infoMessage != nil },
            set: { if !$0 { infoMessage = nil } }
        )) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            if let infoMessage { Text(infoMessage) }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func vendorRow(_ vendor: VendorModel) -> some View {
        let status = VendorInviteStatus.of(invitedAt: vendor.invitedAt, profileId: vendor.profileId?.uuidString)
        let lookup = VendorInviteEligibility.preferredLookup(phone: vendor.phone, email: vendor.email)

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(vendor.name).font(.body.weight(.semibold))
                statusChip(status)
            }
            Spacer()
            if lookup == nil {
                Text(String(localized: "Contact only"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Button(status == .notInvited
                       ? String(localized: "Invite")
                       : String(localized: "Re-send")) {
                    invite(vendor)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isWorking)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func statusChip(_ status: VendorInviteStatus) -> some View {
        switch status {
        case .accepted:
            Label(String(localized: "Accepted"), systemImage: "checkmark.seal.fill")
                .font(.caption2).foregroundStyle(ShiftPalette.live)
        case .invited:
            Label(String(localized: "Invited"), systemImage: "clock.fill")
                .font(.caption2).foregroundStyle(ShiftPalette.warm)
        case .notInvited:
            Label(String(localized: "Not invited"), systemImage: "circle")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: - Composer

    @ViewBuilder
    private func composer(for invite: PendingInvite) -> some View {
        #if canImport(UIKit)
        if let phone = invite.phone {
            MessageComposeView(recipient: phone, body: invite.body) { pendingInvite = nil }
                .ignoresSafeArea()
        } else if let email = invite.email {
            MailComposeView(recipient: email, subject: invite.subject, body: invite.body) { pendingInvite = nil }
                .ignoresSafeArea()
        }
        #else
        EmptyView()
        #endif
    }

    // MARK: - Actions

    /// Marks the vendor invited on Supabase (stamps `invited_at`; `profile_id`
    /// stays null until they claim) and then opens the phone-first composer to
    /// deliver the deep link. Re-sending refreshes `invited_at` and re-delivers.
    private func invite(_ vendor: VendorModel) {
        guard !BlockedContactsStore.shared.isBlocked(phone: vendor.phone, email: vendor.email) else {
            errorMessage = String(localized: "This contact is blocked. Unblock them in Settings → Report a Concern to send an invite.")
            return
        }
        let eventTitle = event?.title ?? ""
        Task { @MainActor in
            isWorking = true
            defer { isWorking = false }
            do {
                try await VendorInviteService(repository: vendorRepo).markInvited(vendor)
                presentDelivery(for: vendor, eventTitle: eventTitle)
            } catch VendorInviteError.notInvitable {
                errorMessage = String(localized: "This vendor has no phone or email, so there's no way to send them an invite.")
            } catch {
                errorMessage = String(localized: "Couldn't send the invite. Please try again.")
            }
        }
    }

    private func presentDelivery(for vendor: VendorModel, eventTitle: String) {
        let message = VendorInviteLink.message(
            eventTitle: eventTitle,
            vendorID: vendor.id,
            eventID: eventID
        )

        switch VendorInviteEligibility.preferredLookup(phone: vendor.phone, email: vendor.email) {
        case .phone(let number):
            #if canImport(UIKit)
            if MessageComposeView.canSend {
                pendingInvite = PendingInvite(phone: number, email: nil, subject: message.subject, body: message.body)
                return
            }
            #endif
            copyInviteLink(for: vendor)
        case .email(let address):
            #if canImport(UIKit)
            if MailComposeView.canSend {
                pendingInvite = PendingInvite(phone: nil, email: address, subject: message.subject, body: message.body)
                return
            }
            #endif
            copyInviteLink(for: vendor)
        case .none:
            copyInviteLink(for: vendor)
        }
    }

    private func copyInviteLink(for vendor: VendorModel) {
        let link = VendorInviteLink.deepLinkString(vendorID: vendor.id, eventID: eventID)
        #if canImport(UIKit)
        UIPasteboard.general.string = link
        #endif
        infoMessage = String(localized: "This device can't send a message, so the invite link was copied. Paste it to the vendor — only the phone or email you invited can accept.")
    }

    // MARK: - Pending invite

    struct PendingInvite: Identifiable {
        let id = UUID()
        let phone: String?
        let email: String?
        let subject: String
        let body: String
    }
}
