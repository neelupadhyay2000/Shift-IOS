import SwiftUI
import SwiftData
import Models
import Services

/// Form sheet for creating or editing a vendor attached to an event.
struct VendorFormSheet: View {

    let eventID: UUID
    let vendorToEdit: VendorModel?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.vendorRepository) private var injectedVendorRepo

    private var vendorRepo: any VendorRepositing {
        injectedVendorRepo ?? SwiftDataVendorRepository(context: modelContext)
    }

    @Query private var results: [EventModel]

    @State private var name = ""
    @State private var role: VendorRole = .photographer
    @State private var customRole = ""
    @State private var phone = ""
    @State private var email = ""

    private var event: EventModel? { results.first { $0.modelContext != nil && !$0.isDeleted } }

    private var isEditing: Bool { vendorToEdit != nil }

    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    init(eventID: UUID, vendor: VendorModel? = nil) {
        self.eventID = eventID
        self.vendorToEdit = vendor
        _results = Query(
            filter: #Predicate<EventModel> { $0.id == eventID }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Info")) {
                    TextField(String(localized: "Name"), text: $name)
                        .textContentType(.name)
                }

                // Visual role picker with colored icons
                Section(String(localized: "Role")) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 12)], spacing: 12) {
                        ForEach(VendorRole.allCases, id: \.self) { r in
                            let roleColor = ShiftDesign.roleColor(for: r)
                            let isSelected = role == r

                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    role = r
                                }
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: r.systemImage)
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundStyle(isSelected ? .white : roleColor)
                                        .frame(width: 44, height: 44)
                                        .background(
                                            isSelected ? roleColor.gradient : Color.clear.gradient,
                                            in: RoundedRectangle(cornerRadius: ShiftDesign.iconRadius, style: .continuous)
                                        )
                                        .background(
                                            isSelected ? Color.clear : roleColor.opacity(0.1),
                                            in: RoundedRectangle(cornerRadius: ShiftDesign.iconRadius, style: .continuous)
                                        )
                                        .symbolEffect(.bounce, value: isSelected)

                                    Text(r.displayName)
                                        .font(.caption2)
                                        .fontWeight(isSelected ? .bold : .medium)
                                        .foregroundStyle(isSelected ? roleColor : .secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    isSelected ? roleColor.opacity(0.06) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(
                                            isSelected ? roleColor.opacity(0.3) : Color.clear,
                                            lineWidth: 1.5
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))

                    // Free-text vendor type for the Custom role — what shows on
                    // the vendor's badge instead of the generic "Custom".
                    if role == .custom {
                        TextField(String(localized: "Vendor type (e.g. Videographer)"), text: $customRole)
                            .accessibilityIdentifier(AccessibilityID.Vendors.customRoleField)
                            .accessibilityLabel(String(localized: "Custom vendor type"))
                    }
                }

                Section(String(localized: "Contact")) {
                    TextField(String(localized: "Phone"), text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)

                    TextField(String(localized: "Email"), text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle(isEditing ? String(localized: "Edit Vendor") : String(localized: "New Vendor"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) { Task { await saveVendor() } }
                        .disabled(!isFormValid)
                }
            }
            .onAppear {
                if let vendorToEdit {
                    name = vendorToEdit.name
                    role = vendorToEdit.role
                    customRole = vendorToEdit.customRoleLabel
                    phone = vendorToEdit.phone
                    email = vendorToEdit.email
                }
            }
        }
    }

    @MainActor
    private func saveVendor() async {
        guard let event else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedPhone = phone.trimmingCharacters(in: .whitespaces)
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        // The label only means something for the Custom role; switching to a
        // built-in role clears any stale label.
        let resolvedCustomLabel = role == .custom
            ? customRole.trimmingCharacters(in: .whitespaces)
            : ""

        if let vendorToEdit {
            vendorToEdit.name = trimmedName
            vendorToEdit.role = role
            vendorToEdit.customRoleLabel = resolvedCustomLabel
            vendorToEdit.phone = trimmedPhone
            vendorToEdit.email = trimmedEmail
        } else {
            let vendor = VendorModel(
                name: trimmedName,
                role: role,
                customRoleLabel: resolvedCustomLabel,
                phone: trimmedPhone,
                email: trimmedEmail
            )
            try? await vendorRepo.insert(vendor, into: event)
            AnalyticsService.send(.vendorInvited)
        }
        dismiss()
    }
}

// MARK: - VendorRole Display

extension VendorRole {
    var displayName: String {
        switch self {
        case .photographer: String(localized: "Photographer")
        case .dj: String(localized: "DJ")
        case .planner: String(localized: "Planner")
        case .caterer: String(localized: "Caterer")
        case .florist: String(localized: "Florist")
        case .custom: String(localized: "Custom")
        }
    }

    var systemImage: String {
        switch self {
        case .photographer: "camera.fill"
        case .dj: "music.note"
        case .planner: "clipboard.fill"
        case .caterer: "fork.knife"
        case .florist: "leaf.fill"
        case .custom: "person.fill"
        }
    }
}
