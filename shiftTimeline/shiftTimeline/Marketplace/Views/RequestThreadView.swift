import SwiftUI

/// Request detail shell: status header, requested-blocks summary, and the vendor's
/// accept/decline bar (or the planner's cancel). The chat body lands in E12.
/// Presented as a sheet from the inbox / my-requests lists.
struct RequestThreadView: View {

    let request: ServiceRequestDTO
    /// Called after a successful respond/cancel so the presenting list can refresh.
    var onResponded: (() -> Void)?

    @Environment(\.serviceRequestService) private var service
    @Environment(\.dismiss) private var dismiss
    @Environment(SupabaseAuthService.self) private var authService

    @State private var status: String
    @State private var message = ""
    @State private var assignedSummary: String?
    @State private var isWorking = false
    @State private var errorMessage: String?

    init(request: ServiceRequestDTO, onResponded: (() -> Void)? = nil) {
        self.request = request
        self.onResponded = onResponded
        _status = State(initialValue: request.status)
    }

    private var isVendor: Bool { request.vendorProfileID == authService.currentProfileID }
    private var isPending: Bool { status == ServiceRequestStatus.pending.rawValue }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    blocksSummary
                    if let note = request.note, !note.isEmpty { noteCard(note) }
                    if let responseMessage = request.responseMessage, !responseMessage.isEmpty {
                        noteCard(responseMessage, label: String(localized: "Response"))
                    }
                    chatPlaceholder
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline).foregroundStyle(.red)
                    }
                }
                .padding(20)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .background { ProBackground() }
            .navigationTitle(String(localized: "Request"))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { actionBar }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                RequestEventSnapshot(
                    title: request.eventTitle,
                    date: request.eventDate?.value,
                    requestedBlockCount: request.requestedBlocks.count
                )
                Spacer()
                RequestStatusChip(status: status)
            }
        }
        .proCard()
    }

    // MARK: Blocks summary

    @ViewBuilder
    private var blocksSummary: some View {
        if !request.requestedBlocks.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(String(localized: "Requested blocks")).microLabel()
                    Spacer()
                    if let assignedSummary {
                        Text(assignedSummary).font(.caption2.weight(.semibold)).foregroundStyle(ShiftPalette.live)
                    }
                }
                VStack(spacing: 8) {
                    ForEach(request.requestedBlocks) { block in
                        HStack {
                            Text(block.title.isEmpty ? String(localized: "Block") : block.title)
                                .font(.subheadline).lineLimit(1)
                            Spacer()
                            Text(block.start.value.formatted(date: .omitted, time: .shortened))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .proCard(padding: 12)
                    }
                }
            }
        }
    }

    private func noteCard(_ text: String, label: String = String(localized: "Note")) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).microLabel()
            Text(text).font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .proCard(padding: 0)
        .padding(.horizontal, 0)
    }

    private var chatPlaceholder: some View {
        Label(String(localized: "Messaging arrives in a future update."), systemImage: "bubble.left.and.bubble.right")
            .font(.caption).foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 8)
    }

    // MARK: Action bar

    @ViewBuilder
    private var actionBar: some View {
        if isPending, service != nil {
            VStack(spacing: 10) {
                if isVendor {
                    TextField(String(localized: "Add a message (optional)"), text: $message)
                        .proCard(padding: 12)
                    HStack(spacing: 12) {
                        Button { Task { await respond(accept: false) } } label: {
                            Text(String(localized: "Decline"))
                                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(ShiftPalette.soft(ShiftPalette.neutral), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.pressableCard)
                        Button { Task { await respond(accept: true) } } label: {
                            Text(String(localized: "Accept"))
                                .font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(ShiftPalette.live.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.pressableCard)
                    }
                } else {
                    Button(role: .destructive) { Task { await cancel() } } label: {
                        Text(String(localized: "Cancel request"))
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(ShiftPalette.soft(.red), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.pressableCard)
                }
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .overlay(alignment: .center) { if isWorking { ProgressView() } }
            .disabled(isWorking)
        }
    }

    // MARK: Actions

    private func respond(accept: Bool) async {
        guard let service else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let result = try await service.respond(requestID: request.id, accept: accept, message: message)
            status = result.status
            if accept {
                assignedSummary = String(localized: "\(result.assignedBlocksCount) of \(request.requestedBlocks.count) blocks assigned")
            }
            onResponded?()
        } catch {
            errorMessage = String(localized: "Couldn't submit your response. Try again.")
        }
    }

    private func cancel() async {
        guard let service else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await service.cancel(requestID: request.id)
            status = ServiceRequestStatus.cancelled.rawValue
            onResponded?()
        } catch {
            errorMessage = String(localized: "Couldn't cancel the request. Try again.")
        }
    }
}
