import Models
import SwiftData
import SwiftUI

/// Compose a service request to a vendor: pick one of my events → optionally pick
/// timeline blocks → note → send. Presented as a sheet from the vendor profile's
/// "Request for an event…" action.
struct RequestComposerView: View {

    let vendorProfileID: UUID
    let vendorName: String

    @Environment(\.serviceRequestService) private var service
    @Environment(\.dismiss) private var dismiss
    @Environment(SupabaseAuthService.self) private var authService
    @Query(sort: \EventModel.date, order: .reverse) private var allEvents: [EventModel]

    @State private var selectedEventID: UUID?
    @State private var selectedBlockIDs: Set<UUID> = []
    @State private var note = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    private var ownedEvents: [EventModel] {
        allEvents.filter { EventAccess.isOwner(ownerId: $0.ownerId, currentProfileID: authService.currentProfileID) }
    }

    private var selectedEvent: EventModel? {
        ownedEvents.first { $0.id == selectedEventID }
    }

    private var blocks: [TimeBlockModel] {
        (selectedEvent?.tracks ?? [])
            .flatMap { $0.blocks ?? [] }
            .sorted { $0.scheduledStart < $1.scheduledStart }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if ownedEvents.isEmpty {
                        ContentUnavailableView(
                            String(localized: "No events yet"),
                            systemImage: "calendar.badge.plus",
                            description: Text(String(localized: "Create an event before requesting a vendor."))
                        )
                        .padding(.top, 40)
                    } else {
                        eventSection
                        if selectedEvent != nil { blockSection }
                        noteSection
                        confirmationCopy
                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline).foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        sendButton
                    }
                }
                .padding(20)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .background { ProBackground() }
            .navigationTitle(String(localized: "Request \(vendorName)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
            }
        }
    }

    // MARK: Event picker

    private var eventSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Event")).microLabel()
            VStack(spacing: 8) {
                ForEach(ownedEvents) { event in
                    let isSelected = selectedEventID == event.id
                    Button {
                        if selectedEventID != event.id {
                            selectedEventID = event.id
                            selectedBlockIDs = []
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isSelected ? ShiftPalette.accent : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title.isEmpty ? String(localized: "Untitled event") : event.title)
                                    .font(.subheadline.weight(.medium)).lineLimit(1)
                                Text(event.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .proCard(padding: 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressableCard)
                }
            }
        }
    }

    // MARK: Block picker

    private var blockSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "Blocks (optional)")).microLabel()
                Spacer()
                if !selectedBlockIDs.isEmpty {
                    Text(String(localized: "\(selectedBlockIDs.count) selected"))
                        .font(.caption2).foregroundStyle(ShiftPalette.accent)
                }
            }
            if blocks.isEmpty {
                Text(String(localized: "This event has no blocks yet."))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(blocks) { block in
                        let isSelected = selectedBlockIDs.contains(block.id)
                        Button {
                            if isSelected { selectedBlockIDs.remove(block.id) } else { selectedBlockIDs.insert(block.id) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(isSelected ? ShiftPalette.accent : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(block.title.isEmpty ? String(localized: "Untitled block") : block.title)
                                        .font(.subheadline).lineLimit(1)
                                    Text(block.scheduledStart.formatted(date: .omitted, time: .shortened))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .proCard(padding: 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.pressableCard)
                    }
                }
            }
        }
    }

    // MARK: Note

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Note (optional)")).microLabel()
            TextField(String(localized: "What do you need from this vendor?"), text: $note, axis: .vertical)
                .lineLimit(3...6)
                .proCard(padding: 14)
        }
    }

    private var confirmationCopy: some View {
        Label(
            String(localized: "When \(vendorName) accepts, they get read access to this event's timeline, and you'll see their contact identity."),
            systemImage: "info.circle"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sendButton: some View {
        Button { Task { await send() } } label: {
            Group {
                if isSending { ProgressView().tint(.white) }
                else { Text(String(localized: "Send request")).font(.headline) }
            }
            .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(ShiftPalette.accent.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.pressableCard)
        .disabled(isSending || selectedEvent == nil || service == nil)
    }

    private func send() async {
        guard let service, let event = selectedEvent else { return }
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            try await service.createRequest(
                eventID: event.id,
                vendorProfileID: vendorProfileID,
                blockIDs: Array(selectedBlockIDs),
                note: note
            )
            Haptics.success()
            dismiss()
        } catch {
            errorMessage = String(localized: "Couldn't send the request. You may already have a pending request for this vendor on this event.")
        }
    }
}
