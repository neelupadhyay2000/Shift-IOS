import SwiftUI

/// Vendor inbox: service requests addressed to me, split into pending and
/// answered. Tapping a row opens the request thread (accept/decline).
struct RequestInboxView: View {

    @Environment(\.serviceRequestService) private var service

    @State private var requests: [ServiceRequestDTO] = []
    @State private var isLoading = true
    @State private var selected: ServiceRequestDTO?

    private var pending: [ServiceRequestDTO] { requests.filter { $0.status == ServiceRequestStatus.pending.rawValue } }
    private var answered: [ServiceRequestDTO] { requests.filter { $0.status != ServiceRequestStatus.pending.rawValue } }

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 60)
            } else if requests.isEmpty {
                ContentUnavailableView(
                    String(localized: "No requests yet"),
                    systemImage: "tray",
                    description: Text(String(localized: "Planners' requests for your services will appear here."))
                )
                .padding(.top, 60)
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    section(String(localized: "Pending"), pending)
                    section(String(localized: "Answered"), answered)
                }
                .padding(20)
                .frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
        }
        .background { ProBackground() }
        .navigationTitle(String(localized: "Event requests"))
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $selected) { request in
            RequestThreadView(request: request) { Task { await load() } }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [ServiceRequestDTO]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).microLabel()
                ForEach(items) { request in
                    Button { selected = request } label: { row(request) }
                        .buttonStyle(.pressableCard)
                }
            }
        }
    }

    private func row(_ request: ServiceRequestDTO) -> some View {
        HStack(spacing: 12) {
            RequestEventSnapshot(
                title: request.eventTitle,
                date: request.eventDate?.value,
                requestedBlockCount: request.requestedBlocks.count
            )
            Spacer(minLength: 0)
            RequestStatusChip(status: request.status)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .proCard(padding: 14)
        .contentShape(Rectangle())
    }

    private func load() async {
        guard let service else { isLoading = false; return }
        isLoading = true
        defer { isLoading = false }
        requests = (try? await service.inbox(limit: 50, offset: 0)) ?? []
    }
}
