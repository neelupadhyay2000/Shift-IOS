import PhotosUI
import SwiftUI

/// Portfolio manager for the signed-in vendor: multi-upload photos to the
/// vendor-portfolio bucket, add server-verified Shift events (only completed
/// events the user worked — listed by `get_claimable_portfolio_events`), edit
/// captions, reorder, and delete.
struct PortfolioEditorView: View {

    @Environment(\.marketplaceService) private var service

    @State private var profileID: UUID?
    @State private var items: [PortfolioItemDTO] = []
    @State private var claimable: [PortfolioEventSummaryDTO] = []
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var isLoading = true
    @State private var isUploading = false
    @State private var isPresentingEventPicker = false
    @State private var captionTarget: PortfolioItemDTO?
    @State private var captionDraft = ""

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                emptyState
            } else {
                itemList
            }
        }
        .background { ProBackground() }
        .navigationTitle(String(localized: "Portfolio"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task { await load() }
        .onChange(of: photoSelection) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task { await uploadPhotos(newItems) }
        }
        .sheet(isPresented: $isPresentingEventPicker) { eventPickerSheet }
        .alert(String(localized: "Caption"), isPresented: captionAlertBinding) {
            TextField(String(localized: "Caption"), text: $captionDraft)
            Button(String(localized: "Save")) { Task { await saveCaption() } }
            Button(String(localized: "Cancel"), role: .cancel) { captionTarget = nil }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if !items.isEmpty {
            ToolbarItem(placement: .topBarLeading) { EditButton() }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                PhotosPicker(selection: $photoSelection, maxSelectionCount: 10, matching: .images) {
                    Label(String(localized: "Add photos"), systemImage: "photo")
                }
                Button {
                    isPresentingEventPicker = true
                } label: {
                    Label(String(localized: "Add a Shift event"), systemImage: "checkmark.seal")
                }
                .disabled(claimable.isEmpty)
            } label: {
                if isUploading { ProgressView() } else { Image(systemName: "plus") }
            }
            .disabled(isUploading)
        }
    }

    // MARK: Item list

    private var itemList: some View {
        List {
            ForEach(items) { item in
                row(item)
            }
            .onMove(perform: move)
            .onDelete(perform: delete)
        }
        .scrollContentBackground(.hidden)
    }

    private func row(_ item: PortfolioItemDTO) -> some View {
        HStack(spacing: 12) {
            thumbnail(item)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.caption?.isEmpty == false ? (item.caption ?? "") :
                        (item.kind == "shift_event" ? String(localized: "Verified event") : String(localized: "Photo")))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                if item.kind == "shift_event" {
                    Label(String(localized: "Verified by Shift"), systemImage: "checkmark.seal.fill")
                        .font(.caption2).foregroundStyle(ShiftPalette.accent)
                }
            }
            Spacer()
            Button {
                captionDraft = item.caption ?? ""
                captionTarget = item
            } label: {
                Image(systemName: "pencil").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private func thumbnail(_ item: PortfolioItemDTO) -> some View {
        if item.kind == "shift_event" {
            Image(systemName: "calendar.badge.checkmark")
                .foregroundStyle(ShiftPalette.accent)
                .frame(width: 48, height: 48)
                .background(ShiftPalette.soft(ShiftPalette.accent), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else if let path = item.storagePath, let url = service?.portfolioImageURL(forPath: path) {
            AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { ProgressView() }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            Image(systemName: "photo").frame(width: 48, height: 48)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(String(localized: "No portfolio items"), systemImage: "photo.on.rectangle.angled")
        } description: {
            Text(String(localized: "Add photos or a Shift event you worked from the + button."))
        }
    }

    // MARK: Event picker

    private var eventPickerSheet: some View {
        NavigationStack {
            List(claimable) { event in
                Button {
                    Task { await addEvent(event) }
                    isPresentingEventPicker = false
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(event.title).font(.subheadline.weight(.medium))
                        Text(event.eventDate.value.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(String(localized: "Add a Shift event"))
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if claimable.isEmpty {
                    ContentUnavailableView(
                        String(localized: "No eligible events"),
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text(String(localized: "Completed events you worked as a vendor will appear here."))
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done")) { isPresentingEventPicker = false }
                }
            }
        }
    }

    // MARK: Caption alert binding

    private var captionAlertBinding: Binding<Bool> {
        Binding(get: { captionTarget != nil }, set: { if !$0 { captionTarget = nil } })
    }

    // MARK: Data

    private func load() async {
        guard let service else { isLoading = false; return }
        isLoading = true
        defer { isLoading = false }
        profileID = try? await service.currentProfileID()
        guard let profileID else { return }
        items = (try? await service.portfolioItems(profileID: profileID)) ?? []
        claimable = (try? await service.claimablePortfolioEvents()) ?? []
    }

    private func uploadPhotos(_ selection: [PhotosPickerItem]) async {
        guard let service, let profileID else { photoSelection = []; return }
        isUploading = true
        defer { isUploading = false; photoSelection = [] }
        for pick in selection {
            guard let data = try? await pick.loadTransferable(type: Data.self),
                  let path = try? await service.uploadPortfolioImage(data: data, fileExtension: "jpg")
            else { continue }
            let item = PortfolioItemDTO(
                profileID: profileID, kind: "photo", storagePath: path, sortOrder: items.count
            )
            if let saved = try? await service.addPortfolioItem(item) {
                items.append(saved)
            }
        }
    }

    private func addEvent(_ event: PortfolioEventSummaryDTO) async {
        guard let service, let profileID else { return }
        let item = PortfolioItemDTO(
            profileID: profileID, kind: "shift_event",
            eventID: event.eventID, caption: event.title, sortOrder: items.count
        )
        if let saved = try? await service.addPortfolioItem(item) {
            items.append(saved)
            claimable.removeAll { $0.eventID == event.eventID }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        let ordered = items.map(\.id)
        Task { try? await service?.reorderPortfolio(orderedIDs: ordered) }
    }

    private func delete(at offsets: IndexSet) {
        let removed = offsets.map { items[$0] }
        items.remove(atOffsets: offsets)
        Task {
            for item in removed {
                try? await service?.deletePortfolioItem(id: item.id)
                // A deleted shift_event becomes claimable again.
                if item.kind == "shift_event" { await reloadClaimable() }
            }
        }
    }

    private func reloadClaimable() async {
        guard let service else { return }
        claimable = (try? await service.claimablePortfolioEvents()) ?? []
    }

    private func saveCaption() async {
        guard let service, let target = captionTarget else { return }
        let updated = PortfolioItemDTO(
            id: target.id, profileID: target.profileID, kind: target.kind,
            storagePath: target.storagePath, eventID: target.eventID,
            caption: captionDraft.trimmingCharacters(in: .whitespacesAndNewlines),
            sortOrder: target.sortOrder
        )
        captionTarget = nil
        if let saved = try? await service.updatePortfolioItem(updated),
           let index = items.firstIndex(where: { $0.id == saved.id }) {
            items[index] = saved
        }
    }
}
