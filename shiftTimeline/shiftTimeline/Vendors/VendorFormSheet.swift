import SwiftUI
import SwiftData
import Models

/// Form sheet for creating or editing a vendor attached to an event.
struct VendorFormSheet: View {

    let eventID: UUID
    let vendorToEdit: VendorModel?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var results: [EventModel]

    @State private var name = ""
    @State private var role: VendorRole = .photographer
    @State private var phone = ""
    @State private var email = ""

    private var event: EventModel? { results.first }

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

                    Picker(String(localized: "Role"), selection: $role) {
                        ForEach(VendorRole.allCases, id: \.self) { role in
                            Text(role.displayName)
                                .tag(role)
                        }
                    }
                }

                Section(String(localized: "Contact")) {
                    TextField(String(localized: "Phone"), text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)

                    TextField(String(localized: "Email"), text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                }
            }
            .navigationTitle(isEditing ? String(localized: "Edit Vendor") : String(localized: "New Vendor"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) { saveVendor() }
                        .disabled(!isFormValid)
                }
            }
            .onAppear {
                if let vendorToEdit {
                    name = vendorToEdit.name
                    role = vendorToEdit.role
                    phone = vendorToEdit.phone
                    email = vendorToEdit.email
                }
            }
        }
    }

    private func saveVendor() {
        guard let event else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedPhone = phone.trimmingCharacters(in: .whitespaces)
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)

        if let vendorToEdit {
            vendorToEdit.name = trimmedName
            vendorToEdit.role = role
            vendorToEdit.phone = trimmedPhone
            vendorToEdit.email = trimmedEmail
        } else {
            let vendor = VendorModel(
                name: trimmedName,
                role: role,
                phone: trimmedPhone,
                email: trimmedEmail
            )
            vendor.event = event
            modelContext.insert(vendor)
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
