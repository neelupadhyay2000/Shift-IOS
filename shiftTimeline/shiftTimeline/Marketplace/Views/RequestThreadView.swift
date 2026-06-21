import SwiftUI

/// Request detail + chat. Top: a compact request card (status, event snapshot,
/// requested-blocks summary). Body: realtime message bubbles. Bottom: the pending
/// accept/decline (vendor) or cancel (planner) action row plus the chat composer.
/// Presented as a sheet from the inbox / my-requests lists.
struct RequestThreadView: View {

    let request: ServiceRequestDTO
    /// Called after a successful respond/cancel so the presenting list can refresh.
    var onResponded: (() -> Void)?

    @Environment(\.serviceRequestService) private var serviceRequests
    @Environment(\.requestMessagingService) private var messaging
    @Environment(\.contentReportService) private var contentReports
    @Environment(SupabaseAuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss

    @State private var status: String
    @State private var assignedSummary: String?
    @State private var isWorking = false
    @State private var errorMessage: String?

    @State private var live: RequestThreadLive?
    @State private var composerText = ""
    @State private var reportTarget: RequestMessageDTO?

    init(request: ServiceRequestDTO, onResponded: (() -> Void)? = nil) {
        self.request = request
        self.onResponded = onResponded
        _status = State(initialValue: request.status)
    }

    private var me: UUID? { authService.currentProfileID }
    private var isVendor: Bool { request.vendorProfileID == me }
    private var isPending: Bool { status == ServiceRequestStatus.pending.rawValue }
    private var messages: [RequestMessageDTO] { live?.messages ?? [] }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        detailCard
                        ForEach(messages) { message in
                            bubble(message).id(message.id)
                        }
                        Color.clear.frame(height: 1).id(bottomAnchor)
                    }
                    .padding(16)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: messages.count) { _, _ in scrollToBottom(proxy) }
                .onChange(of: live == nil) { _, _ in scrollToBottom(proxy) }
            }
            .background { ProBackground() }
            .navigationTitle(String(localized: "Request"))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { bottomBar }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
            .task { await setup() }
            .onDisappear { live?.stop() }
            .sheet(item: $reportTarget) { message in
                ReportReasonSheet(contentType: .message, contentID: message.id)
            }
        }
    }

    private let bottomAnchor = "thread-bottom"

    // MARK: Detail card

    private var detailCard: some View {
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
            if let assignedSummary {
                Label(assignedSummary, systemImage: "checkmark.seal.fill")
                    .font(.caption2.weight(.semibold)).foregroundStyle(ShiftPalette.live)
            }
            if let note = request.note, !note.isEmpty {
                Text(note).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .proCard()
    }

    // MARK: Bubbles

    private func bubble(_ message: RequestMessageDTO) -> some View {
        let isMine = message.senderID == me
        return HStack {
            if isMine { Spacer(minLength: 40) }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 3) {
                Text(message.body)
                    .font(.subheadline)
                    .foregroundStyle(isMine ? .white : .primary)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(
                        isMine ? AnyShapeStyle(ShiftPalette.accent.gradient)
                               : AnyShapeStyle(ShiftPalette.soft(ShiftPalette.neutral)),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                Text(message.createdAt.value.formatted(date: .omitted, time: .shortened))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .contextMenu {
                if !isMine {
                    Button { reportTarget = message } label: {
                        Label(String(localized: "Report message"), systemImage: "flag")
                    }
                    Button(role: .destructive) { Task { await block(message.senderID) } } label: {
                        Label(String(localized: "Block sender"), systemImage: "hand.raised")
                    }
                }
            }
            if !isMine { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
    }

    // MARK: Bottom bar (actions + composer)

    @ViewBuilder
    private var bottomBar: some View {
        VStack(spacing: 10) {
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
            if isPending, serviceRequests != nil {
                pendingActions
            }
            composer
        }
        .padding(12)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var pendingActions: some View {
        if isVendor {
            HStack(spacing: 10) {
                Button { Task { await respond(accept: false) } } label: {
                    Text(String(localized: "Decline")).font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(ShiftPalette.soft(ShiftPalette.neutral), in: Capsule())
                }
                .buttonStyle(.pressableCard)
                Button { Task { await respond(accept: true) } } label: {
                    Text(String(localized: "Accept")).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(ShiftPalette.live.gradient, in: Capsule())
                }
                .buttonStyle(.pressableCard)
            }
            .disabled(isWorking)
        } else {
            Button(role: .destructive) { Task { await cancelRequest() } } label: {
                Text(String(localized: "Cancel request")).font(.subheadline.weight(.semibold)).foregroundStyle(.red)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(ShiftPalette.soft(.red), in: Capsule())
            }
            .buttonStyle(.pressableCard)
            .disabled(isWorking)
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField(String(localized: "Message"), text: $composerText, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(ShiftPalette.soft(ShiftPalette.neutral), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Button { send() } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
            .disabled(composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || messaging == nil)
            .tint(ShiftPalette.accent)
        }
    }

    // MARK: Actions

    private func setup() async {
        guard let messaging else { return }
        let thread = messaging.makeThreadLive(requestID: request.id)
        live = thread
        let page = (try? await messaging.messages(requestID: request.id, before: nil, limit: 50)) ?? []
        thread.seed(page)
        thread.start()
    }

    private func send() {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let messaging, let thread = live, let me else { return }
        composerText = ""
        let clientID = UUID()
        // Optimistic: show immediately; the realtime echo / server row dedupes by id.
        thread.apply(RequestMessageDTO(
            id: clientID, requestID: request.id, senderID: me, body: text,
            createdAt: PostgresTimestamp(Date())
        ))
        Task {
            if let saved = try? await messaging.send(requestID: request.id, body: text, clientID: clientID) {
                thread.apply(saved)
            }
        }
    }

    private func block(_ senderID: UUID) async {
        guard let contentReports else { return }
        try? await contentReports.block(profileID: senderID)
        // 1:1 thread — once the other participant is blocked, leave the thread.
        dismiss()
    }

    private func respond(accept: Bool) async {
        guard let serviceRequests else { return }
        isWorking = true; errorMessage = nil
        defer { isWorking = false }
        do {
            let result = try await serviceRequests.respond(requestID: request.id, accept: accept, message: nil)
            status = result.status
            if accept {
                assignedSummary = String(localized: "\(result.assignedBlocksCount) of \(request.requestedBlocks.count) blocks assigned")
            }
            onResponded?()
        } catch {
            errorMessage = String(localized: "Couldn't submit your response. Try again.")
        }
    }

    private func cancelRequest() async {
        guard let serviceRequests else { return }
        isWorking = true; errorMessage = nil
        defer { isWorking = false }
        do {
            try await serviceRequests.cancel(requestID: request.id)
            status = ServiceRequestStatus.cancelled.rawValue
            onResponded?()
        } catch {
            errorMessage = String(localized: "Couldn't cancel the request. Try again.")
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard !messages.isEmpty else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(bottomAnchor, anchor: .bottom)
        }
    }
}
