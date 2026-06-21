import Models
import SwiftData
import SwiftUI

/// Lists a completed event's claimed vendors so the planner can review each one.
/// Launched from the post-event report / completed event detail. Only vendors who
/// actually claimed (have a `profileId` + `acceptedAt`) can be reviewed — that's
/// the same set the `submit_vendor_review` RPC accepts.
struct ReviewVendorsSheet: View {

    let eventID: UUID

    @Environment(\.dismiss) private var dismiss
    @Query private var results: [EventModel]
    @State private var target: ReviewTarget?

    init(eventID: UUID) {
        self.eventID = eventID
        _results = Query(filter: #Predicate<EventModel> { $0.id == eventID })
    }

    private var event: EventModel? { results.first }

    /// Claimed vendors only (signed-in collaborators), sorted by name.
    private var claimedVendors: [VendorModel] {
        (event?.vendors ?? [])
            .filter { $0.profileId != nil && $0.acceptedAt != nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Group {
                if claimedVendors.isEmpty {
                    ContentUnavailableView(
                        String(localized: "No vendors to review"),
                        systemImage: "person.2.slash",
                        description: Text(String(localized: "Only vendors who joined this event can be reviewed."))
                    )
                } else {
                    List(claimedVendors, id: \.id) { vendor in
                        Button {
                            if let profileID = vendor.profileId {
                                target = ReviewTarget(id: profileID, name: vendor.name)
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(vendor.name).font(.body.weight(.medium))
                                    Text(VendorRoleLabel.display(role: vendor.role, customLabel: vendor.customRoleLabel))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "star.bubble")
                                    .foregroundStyle(ShiftPalette.accent)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .accessibilityIdentifier(AccessibilityID.Marketplace.reviewVendorsList)
                }
            }
            .navigationTitle(String(localized: "Review your vendors"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
            .sheet(item: $target) { target in
                ReviewComposerView(
                    eventID: eventID,
                    vendorProfileID: target.id,
                    vendorName: target.name
                )
            }
        }
    }
}

/// Identifies the vendor whose composer is open (id = vendor's profile id).
private struct ReviewTarget: Identifiable {
    let id: UUID
    let name: String
}
