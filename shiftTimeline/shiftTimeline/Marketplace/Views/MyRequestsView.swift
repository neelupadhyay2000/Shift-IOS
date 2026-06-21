import SwiftUI

/// Planner view of requests they've sent, grouped by event, with status chips and
/// a cancel action (via the thread). Reached from the Marketplace tab.
struct MyRequestsView: View {

    @Environment(\.serviceRequestService) private var service

    @State private var requests: [ServiceRequestDTO] = []
    @State private var isLoading = true
    @State private var selected: ServiceRequestDTO?

    /// Requests grouped by event, each group ordered newest-first, groups ordered
    /// by the most recent request in them.
    private var groups: [(eventID: UUID, title: String, items: [ServiceRequestDTO])] {
        let byEvent = Dictionary(grouping: requests, by: \.eventID)
        return byEvent
            .map { (key, value) in
                let sorted = value.sorted { ($0.createdAt?.value ?? .distantPast) > ($1.createdAt?.value ?? .distantPast) }
                return (eventID: key, title: sorted.first?.eventTitle ?? "", items: sorted)
            }
            .sorted { ($0.items.first?.createdAt?.value ?? .distantPast) > ($1.items.first?.createdAt?.value ?? .distantPast) }
    }

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 60)
            } else if requests.isEmpty {
                ContentUnavailableView(
                    String(localized: "No requests sent"),
                    systemImage: "paperplane",
                    description: Text(String(localized: "Requests you send to vendors will appear here."))
                )
                .padding(.top, 60)
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(groups, id: \.eventID) { group in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(group.title.isEmpty ? String(localized: "Event") : group.title).microLabel()
                            ForEach(group.items) { request in
                                Button { selected = request } label: { row(request) }
                                    .buttonStyle(.pressableCard)
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
        }
        .background { ProBackground() }
        .navigationTitle(String(localized: "My requests"))
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $selected) { request in
            RequestThreadView(request: request) { Task { await load() } }
        }
    }

    private func row(_ request: ServiceRequestDTO) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "Vendor request")).font(.subheadline.weight(.medium))
                HStack(spacing: 10) {
                    if let created = request.createdAt?.value {
                        Label(created.formatted(date: .abbreviated, time: .omitted), systemImage: "paperplane")
                    }
                    if !request.requestedBlocks.isEmpty {
                        Label(String(localized: "\(request.requestedBlocks.count) blocks"), systemImage: "rectangle.stack")
                    }
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
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
        requests = (try? await service.myRequests(limit: 100, offset: 0)) ?? []
    }
}
