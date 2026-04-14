import SwiftUI
import SwiftData
import Models

struct VendorManagerView: View {

    let eventID: UUID

    @Environment(\.modelContext) private var modelContext
    @Query private var results: [EventModel]
    @State private var showingAddSheet = false
    @State private var vendorToEdit: VendorModel?
    @State private var vendorToDelete: VendorModel?
    @State private var showDeleteConfirmation = false

    private var event: EventModel? { results.first }

    init(eventID: UUID) {
        self.eventID = eventID
        _results = Query(
            filter: #Predicate<EventModel> { $0.id == eventID }
        )
    }

    var body: some View {
        List {
            if let event {
                if event.vendors.isEmpty {
                    ContentUnavailableView(
                        String(localized: "No Vendors"),
                        systemImage: "person.2.slash",
                        description: Text(String(localized: "Tap + to add a vendor."))
                    )
                } else {
                    ForEach(event.vendors.sorted(by: { $0.name < $1.name })) { vendor in
                        Button {
                            vendorToEdit = vendor
                        } label: {
                            vendorRow(vendor)
                        }
                        .tint(.primary)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                requestDelete(vendor)
                            } label: {
                                Label(String(localized: "Delete"), systemImage: "trash")
                            }
                        }
                    }
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
        HStack(spacing: 12) {
            Image(systemName: vendor.role.systemImage)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.gradient, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(vendor.name)
                    .font(.headline)
                Text(vendor.role.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
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
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func assignedBlockCount(for vendor: VendorModel) -> Int {
        guard let event else { return 0 }
        return event.tracks
            .flatMap(\.blocks)
            .filter { $0.vendors.contains(where: { $0.id == vendor.id }) }
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
            for block in event.tracks.flatMap(\.blocks) {
                block.vendors.removeAll(where: { $0.id == vendor.id })
            }
        }
        modelContext.delete(vendor)
        vendorToDelete = nil
    }
}
