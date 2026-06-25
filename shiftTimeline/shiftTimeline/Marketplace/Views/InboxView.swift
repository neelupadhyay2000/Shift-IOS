import SwiftUI

/// Unified marketplace inbox — every request conversation in one place, since chat
/// lives inside each request. Merges requests received (as a vendor) and sent (as
/// a planner). Pending requests addressed to you surface in "Needs your response";
/// everything else is a recency-sorted conversation list. Tapping a row opens the
/// request thread (accept/decline/cancel + chat).
struct InboxView: View {

    @Environment(\.serviceRequestService) private var service
    @Environment(SupabaseAuthService.self) private var authService

    /// A request plus which side of it the signed-in user is on.
    private struct Item: Identifiable {
        let request: ServiceRequestDTO
        let incoming: Bool          // true = received (I'm the vendor)
        var id: UUID { request.id }
    }

    @State private var items: [Item] = []
    @State private var isLoading = true
    @State private var selected: ServiceRequestDTO?

    /// Incoming + still pending → the user needs to act (accept/decline).
    private var needsResponse: [Item] {
        items.filter { $0.incoming && $0.request.status == ServiceRequestStatus.pending.rawValue }
    }

    private var conversations: [Item] {
        let actionable = Set(needsResponse.map(\.id))
        return items.filter { !actionable.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 60)
            } else if items.isEmpty {
                ContentUnavailableView(
                    String(localized: "No conversations yet"),
                    systemImage: "tray",
                    description: Text(String(localized: "Requests you send to vendors and requests for your services both land here."))
                )
                .padding(.top, 60)
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    section(String(localized: "Needs your response"), needsResponse)
                    section(String(localized: "Conversations"), conversations)
                }
                .padding(20)
                .frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
        }
        .background { ProBackground() }
        .navigationTitle(String(localized: "Inbox"))
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $selected) { request in
            RequestThreadView(request: request) { Task { await load() } }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [Item]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).microLabel()
                ForEach(items) { item in
                    Button { selected = item.request } label: { row(item) }
                        .buttonStyle(.pressableCard)
                }
            }
        }
    }

    private func row(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                RequestEventSnapshot(
                    title: item.request.eventTitle,
                    date: item.request.eventDate?.value,
                    requestedBlockCount: item.request.requestedBlocks.count
                )
                Spacer(minLength: 0)
                RequestStatusChip(status: item.request.status)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            Divider().opacity(0.5)
            Label(
                item.incoming ? String(localized: "Request for your services") : String(localized: "You requested a vendor"),
                systemImage: item.incoming ? "tray.and.arrow.down" : "paperplane"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .proCard(padding: 14)
        .contentShape(Rectangle())
    }

    private func load() async {
        guard let service else { isLoading = false; return }
        isLoading = true
        defer { isLoading = false }
        // Exclusive personas: a vendor only has requests RECEIVED; a planner only
        // has requests SENT. Load just that side so the inbox stays separated.
        if authService.isVendorAccount {
            items = ((try? await service.inbox(limit: 100, offset: 0)) ?? [])
                .map { Item(request: $0, incoming: true) }
        } else {
            items = ((try? await service.myRequests(limit: 100, offset: 0)) ?? [])
                .map { Item(request: $0, incoming: false) }
        }
        items.sort {
            ($0.request.createdAt?.value ?? .distantPast) > ($1.request.createdAt?.value ?? .distantPast)
        }
    }
}
