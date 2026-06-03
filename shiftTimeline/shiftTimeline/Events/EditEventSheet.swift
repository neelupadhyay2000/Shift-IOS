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
    @Environment(\.eventRepository) private var injectedEventRepo

    private var eventRepo: any EventRepositing {
        injectedEventRepo ?? SwiftDataEventRepository(context: modelContext)
    }

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
                    DatePickerRow(
                        String(localized: "Date"),
                        selection: $date,
                        components: .date
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
                        Task { await saveChanges() }
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    @MainActor
    private func saveChanges() async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let newLatitude = locationResult?.coordinate?.latitude ?? 0
        let newLongitude = locationResult?.coordinate?.longitude ?? 0
        let locationChanged = newLatitude != event.latitude || newLongitude != event.longitude
        let dateChanged = date != event.date

        event.title = trimmedTitle
        event.date = date
        event.latitude = newLatitude
        event.longitude = newLongitude
        event.venueNames = {
            guard let name = locationResult?.venueName, !name.isEmpty else { return [] }
            return [name]
        }()

        // Bust weather + sunset caches whenever the venue or date changes so the
        // next fetch returns data for the correct location and day.
        if locationChanged || dateChanged {
            event.weatherSnapshot = nil
            event.sunsetTime = nil
            event.goldenHourStart = nil
        }

        event.touchForSync()
        try? await eventRepo.save()

        // Immediately write child parent-fields to CloudKit so participants receive
        // a push notification for this edit without waiting for NSPersistentCloudKitContainer's
        // batched sync — which can take minutes and is the root cause of stale vendor views.
        Task { await CloudKitShareRepairService.repairParentFieldsIfShared(for: event) }

        if (locationChanged || dateChanged) && (newLatitude != 0 || newLongitude != 0) {
            let service = SunsetService()
            _ = await service.fetchIfNeeded(for: event)
            try? await eventRepo.save()
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
