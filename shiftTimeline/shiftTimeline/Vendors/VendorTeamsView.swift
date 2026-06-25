import Models
import Services
import SwiftUI

/// Settings-level manager for reusable vendor teams.
///
/// Teams are device-local snapshots of the people a planner works with
/// regularly ("Wedding A-Team"). Applying a team from an event's vendor
/// manager materialises fresh `VendorModel` rows, so each event still owns
/// its vendors (and their per-event invite/ack state).
struct VendorTeamsView: View {

    @State private var teams: [VendorTeam] = []
    @State private var editingTeam: VendorTeam?
    @State private var isCreatingTeam = false
    @State private var teamPendingDeletion: VendorTeam?

    private let store = VendorTeamStore()

    var body: some View {
        Group {
            if teams.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "No Vendor Teams"), systemImage: "person.3")
                } description: {
                    Text(String(localized: """
                    Create a team of vendors you work with regularly, \
                    then add them to any event in one tap.
                    """))
                } actions: {
                    Button(String(localized: "Create Team")) {
                        isCreatingTeam = true
                    }
                }
            } else {
                List {
                    ForEach(teams) { team in
                        Button {
                            editingTeam = team
                        } label: {
                            teamRow(team)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        teamPendingDeletion = offsets.first.map { teams[$0] }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background { ProBackground() }
        .navigationTitle(String(localized: "Vendor Teams"))
        .navigationBarTitleDisplayMode(.large)
        .accessibilityIdentifier(AccessibilityID.VendorTeams.teamList)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isCreatingTeam = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(String(localized: "Add Team"))
                .accessibilityIdentifier(AccessibilityID.VendorTeams.addTeamButton)
            }
        }
        .onAppear { reload() }
        .sheet(isPresented: $isCreatingTeam) {
            VendorTeamEditorSheet(team: VendorTeam(name: "")) { newTeam in
                persist(newTeam, isNew: true)
            }
        }
        .sheet(item: $editingTeam) { team in
            VendorTeamEditorSheet(team: team) { updated in
                persist(updated, isNew: false)
            }
        }
        .confirmationDialog(
            String(localized: "Delete Team?"),
            isPresented: Binding(
                get: { teamPendingDeletion != nil },
                set: { if !$0 { teamPendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: teamPendingDeletion
        ) { team in
            Button(String(localized: "Delete"), role: .destructive) {
                delete(team)
            }
        } message: { team in
            Text(String(localized: """
            “\(team.name)” will be removed. \
            Vendors already added to events are not affected.
            """))
        }
    }

    private func teamRow(_ team: VendorTeam) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(ShiftPalette.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(team.name)
                    .font(.subheadline.weight(.semibold))
                Text(membersSummary(team))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(String(localized: "Double tap to edit team"))
    }

    private func membersSummary(_ team: VendorTeam) -> String {
        guard !team.members.isEmpty else {
            return String(localized: "No members yet")
        }
        return team.members.map(\.name).joined(separator: ", ")
    }

    private func reload() {
        teams = (try? store.loadAll()) ?? []
    }

    private func persist(_ team: VendorTeam, isNew: Bool) {
        try? store.save(team)
        if isNew {
            AnalyticsService.send(.vendorTeamCreated, parameters: ["memberCount": "\(team.members.count)"])
        }
        reload()
    }

    private func delete(_ team: VendorTeam) {
        try? store.delete(id: team.id)
        reload()
    }
}

// MARK: - Previews

#Preview {
    NavigationStack {
        VendorTeamsView()
    }
}
