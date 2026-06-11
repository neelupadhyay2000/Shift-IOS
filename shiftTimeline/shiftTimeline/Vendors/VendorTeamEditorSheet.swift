import Models
import Services
import SwiftUI

/// Editor sheet for a vendor team: team name plus the member list (add, edit,
/// remove). Works on value copies — nothing persists until Save hands the
/// rebuilt `VendorTeam` (same ID) back to the caller.
struct VendorTeamEditorSheet: View {

    let team: VendorTeam
    let onSave: (VendorTeam) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var members: [VendorTeamMember]

    init(team: VendorTeam, onSave: @escaping (VendorTeam) -> Void) {
        self.team = team
        self.onSave = onSave
        _name = State(initialValue: team.name)
        _members = State(initialValue: team.members)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && members.contains { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Team")) {
                    TextField(String(localized: "Team Name"), text: $name)
                        .accessibilityIdentifier(AccessibilityID.VendorTeams.teamNameField)
                }

                Section {
                    ForEach($members) { $member in
                        NavigationLink {
                            VendorTeamMemberForm(member: $member)
                        } label: {
                            memberRow(member)
                        }
                    }
                    .onDelete { offsets in
                        members.remove(atOffsets: offsets)
                    }

                    Button {
                        members.append(VendorTeamMember(name: "", role: .photographer))
                    } label: {
                        Label(String(localized: "Add Member"), systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text(String(localized: "Members"))
                } footer: {
                    if members.isEmpty {
                        Text(String(localized: "A team needs at least one member."))
                    } else {
                        Text(String(localized: "Swipe a member to remove them from the team."))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { ProBackground() }
            .navigationTitle(team.name.isEmpty
                ? String(localized: "New Team")
                : String(localized: "Edit Team"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        saveTeam()
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier(AccessibilityID.VendorTeams.editorSaveButton)
                }
            }
        }
    }

    private func memberRow(_ member: VendorTeamMember) -> some View {
        let roleColor = ShiftDesign.roleColor(for: member.role)
        return HStack(spacing: 12) {
            Image(systemName: member.role.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(roleColor.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(member.name.isEmpty ? String(localized: "New Member") : member.name)
                    .font(.subheadline.weight(.medium))
                Text(VendorRoleLabel.display(role: member.role, customLabel: member.customRoleLabel))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func saveTeam() {
        let kept = members
            .map { member in
                var trimmed = member
                trimmed.name = member.name.trimmingCharacters(in: .whitespaces)
                // The label only means something for the Custom role.
                trimmed.customRoleLabel = member.role == .custom
                    ? member.customRoleLabel.trimmingCharacters(in: .whitespaces)
                    : ""
                trimmed.phone = member.phone.trimmingCharacters(in: .whitespaces)
                trimmed.email = member.email.trimmingCharacters(in: .whitespaces)
                return trimmed
            }
            .filter { !$0.name.isEmpty }

        let updated = VendorTeam(
            id: team.id,
            name: name.trimmingCharacters(in: .whitespaces),
            members: kept
        )
        onSave(updated)
        dismiss()
    }
}

// MARK: - Member form

private struct VendorTeamMemberForm: View {

    @Binding var member: VendorTeamMember

    var body: some View {
        Form {
            Section(String(localized: "Member")) {
                TextField(String(localized: "Name"), text: $member.name)
                Picker(String(localized: "Role"), selection: $member.role) {
                    ForEach(VendorRole.allCases, id: \.self) { role in
                        Text(role.displayName).tag(role)
                    }
                }
                // Free-text vendor type for the Custom role — shown on the
                // member's badge and carried onto vendors created from the team.
                if member.role == .custom {
                    TextField(String(localized: "Vendor type (e.g. Videographer)"), text: $member.customRoleLabel)
                        .accessibilityIdentifier(AccessibilityID.VendorTeams.memberCustomRoleField)
                        .accessibilityLabel(String(localized: "Custom vendor type"))
                }
            }

            Section(String(localized: "Contact")) {
                TextField(String(localized: "Phone"), text: $member.phone)
                    .keyboardType(.phonePad)
                TextField(String(localized: "Email"), text: $member.email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .scrollContentBackground(.hidden)
        .background { ProBackground() }
        .navigationTitle(member.name.isEmpty ? String(localized: "New Member") : member.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
