import Models
import Services
import SwiftData
import SwiftUI

/// Sheet that applies a saved vendor team to one event.
///
/// Picking a team creates a fresh `VendorModel` row per member (routed through
/// the vendor repository so they sync), skipping members who already exist on
/// the event by name — re-applying a team is safe and additive.
struct ApplyVendorTeamSheet: View {

    let eventID: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.vendorRepository) private var injectedVendorRepo
    @Query private var results: [EventModel]

    @State private var teams: [VendorTeam] = []
    @State private var isApplying = false

    private var event: EventModel? { results.first { $0.modelContext != nil && !$0.isDeleted } }

    private var vendorRepo: any VendorRepositing {
        injectedVendorRepo ?? SwiftDataVendorRepository(context: modelContext)
    }

    init(eventID: UUID) {
        self.eventID = eventID
        _results = Query(
            filter: #Predicate<EventModel> { $0.id == eventID }
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if teams.isEmpty {
                    ContentUnavailableView {
                        Label(String(localized: "No Vendor Teams"), systemImage: "person.3")
                    } description: {
                        Text(String(localized: """
                        Create reusable teams in Settings → Vendor Teams, \
                        then add a whole crew to any event in one tap.
                        """))
                    }
                } else {
                    List(teams) { team in
                        Button {
                            apply(team)
                        } label: {
                            teamRow(team)
                        }
                        .buttonStyle(.plain)
                        .disabled(isApplying)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background { ProBackground() }
            .navigationTitle(String(localized: "Add Team"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                teams = (try? VendorTeamStore().loadAll()) ?? []
            }
        }
    }

    private func teamRow(_ team: VendorTeam) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(ShiftPalette.accent.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(team.name)
                    .font(.subheadline.weight(.semibold))
                Text(String(localized: "\(team.members.count) members — \(newMemberCount(team)) new for this event"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "plus.circle.fill")
                .foregroundStyle(ShiftPalette.accent)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(String(localized: "Adds this team's vendors to the event"))
    }

    /// Members not already on the event (matched case-insensitively by name).
    private func newMembers(of team: VendorTeam) -> [VendorTeamMember] {
        let existingNames = Set(
            (event?.vendors ?? []).map { $0.name.lowercased().trimmingCharacters(in: .whitespaces) }
        )
        return team.members.filter {
            !existingNames.contains($0.name.lowercased().trimmingCharacters(in: .whitespaces))
        }
    }

    private func newMemberCount(_ team: VendorTeam) -> Int {
        newMembers(of: team).count
    }

    private func apply(_ team: VendorTeam) {
        guard let event, !isApplying else { return }
        let toAdd = newMembers(of: team)
        guard !toAdd.isEmpty else {
            dismiss()
            return
        }
        isApplying = true
        Task {
            for member in toAdd {
                let vendor = VendorModel(
                    name: member.name,
                    role: member.role,
                    customRoleLabel: member.customRoleLabel,
                    phone: member.phone,
                    email: member.email
                )
                try? await vendorRepo.insert(vendor, into: event)
            }
            try? await vendorRepo.save()
            AnalyticsService.send(.vendorTeamApplied, parameters: ["memberCount": "\(toAdd.count)"])
            dismiss()
        }
    }
}
