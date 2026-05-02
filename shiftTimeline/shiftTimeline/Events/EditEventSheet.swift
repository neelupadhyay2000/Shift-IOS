import SwiftUI
import SwiftData
import MapKit
import Models
import Services

/// Sheet for editing an existing event's metadata: title, date, and venue.
///
/// Local `@State` copies are used so that "Cancel" discards all changes
/// without touching the model. On "Save", the changes are written back
/// to the `EventModel` and the context is persisted.
struct EditEventSheet: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let event: EventModel

    @State private var title: String
    @State private var date: Date
    @State private var locationResult: BlockLocationResult?

    init(event: EventModel) {
        self.event = event
        _title = State(initialValue: event.title)
        _date = State(initialValue: event.date)
        let hasCoordinate = event.latitude != 0 || event.longitude != 0
        _locationResult = State(initialValue: hasCoordinate
            ? BlockLocationResult(
                venueName: event.venueNames.first ?? "",
                venueAddress: "",
                coordinate: CLLocationCoordinate2D(
                    latitude: event.latitude,
                    longitude: event.longitude
                )
              )
            : nil
        )
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Title"), text: $title)
                    DatePicker(
                        String(localized: "Date"),
                        selection: $date,
                        displayedComponents: .date
                    )
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
            .navigationTitle(String(localized: "Edit Event"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        saveChanges()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private func saveChanges() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let newLatitude = locationResult?.coordinate?.latitude ?? 0
        let newLongitude = locationResult?.coordinate?.longitude ?? 0
        let locationChanged = newLatitude != event.latitude || newLongitude != event.longitude

        event.title = trimmedTitle
        event.date = date
        event.latitude = newLatitude
        event.longitude = newLongitude
        event.venueNames = {
            guard let name = locationResult?.venueName, !name.isEmpty else { return [] }
            return [name]
        }()

        // Bust the weather cache when the venue changes so a fresh fetch runs.
        if locationChanged {
            event.weatherSnapshot = nil
        }

        try? modelContext.save()

        if locationChanged && (newLatitude != 0 || newLongitude != 0) {
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
    let container = try! PersistenceController.forTesting()
    let event = EventModel(
        title: "Sample Wedding",
        date: .now,
        latitude: 37.3316,
        longitude: -122.0302,
        venueNames: ["Apple Park"]
    )
    return EditEventSheet(event: event)
        .modelContainer(container)
}
