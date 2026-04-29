import SwiftUI
import SwiftData
import MapKit
import Models
import Services

/// Sheet for creating a new event.
///
/// Fields: Title (required), Date, Location (optional address search).
/// The "Create" button is disabled when title is empty.
struct CreateEventSheet: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var date: Date = .now
    @State private var locationResult: BlockLocationResult? = nil

    private var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Title"), text: $title)
                        .accessibilityIdentifier(AccessibilityID.EventCreation.titleField)
                    DatePicker(String(localized: "Date"), selection: $date, displayedComponents: .date)
                        .accessibilityIdentifier(AccessibilityID.EventCreation.datePicker)
                }

                Section(String(localized: "Location")) {
                    BlockLocationPickerView(
                        currentAddress: locationResult?.venueAddress ?? "",
                        currentVenueName: locationResult?.venueName ?? ""
                    ) { result in
                        locationResult = result.coordinate == nil ? nil : result
                    }
                }
            }
            .navigationTitle(String(localized: "New Event"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                    }
                    .accessibilityIdentifier(AccessibilityID.EventCreation.cancelButton)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Create")) {
                        createEvent()
                    }
                    .disabled(!canCreate)
                    .accessibilityHint(canCreate ? "" : String(localized: "Enter an event title to continue"))
                    .accessibilityIdentifier(AccessibilityID.EventCreation.createButton)
                }
            }
        }
    }

    private func createEvent() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let latitude = locationResult?.coordinate?.latitude ?? 0
        let longitude = locationResult?.coordinate?.longitude ?? 0
        let venueNames: [String] = {
            guard let name = locationResult?.venueName, !name.isEmpty else { return [] }
            return [name]
        }()

        let event = EventModel(
            title: trimmedTitle,
            date: date,
            latitude: latitude,
            longitude: longitude,
            venueNames: venueNames
        )
        event.ownerRecordName = CloudKitIdentity.shared.currentUserRecordName
        modelContext.insert(event)
        AnalyticsService.send(.eventCreated)

        let mainTrack = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true, event: event)
        modelContext.insert(mainTrack)

        // Fire-and-forget sunset fetch when both coordinates are provided.
        if latitude != 0 && longitude != 0 {
            Task { @MainActor in
                let service = SunsetService()
                _ = await service.fetchIfNeeded(for: event)
                try? modelContext.save()
            }
        }

        dismiss()
    }
}

#Preview {
    CreateEventSheet()
        .modelContainer(try! PersistenceController.forTesting())
}
