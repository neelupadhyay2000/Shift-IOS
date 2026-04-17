import SwiftUI
import SwiftData
import Models
import Services

/// Sheet for creating a new event.
///
/// Fields: Title (required), Date, Venue Name (optional).
/// The "Create" button is disabled when title is empty.
struct CreateEventSheet: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var date: Date = .now
    @State private var venueName: String = ""
    @State private var latitudeText: String = ""
    @State private var longitudeText: String = ""

    private var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Title"), text: $title)
                    DatePicker(String(localized: "Date"), selection: $date, displayedComponents: .date)
                    TextField(String(localized: "Venue Name"), text: $venueName)
                }

                Section(String(localized: "Location")) {
                    TextField(String(localized: "Latitude"), text: $latitudeText)
                        .keyboardType(.numbersAndPunctuation)
                    TextField(String(localized: "Longitude"), text: $longitudeText)
                        .keyboardType(.numbersAndPunctuation)
                }
            }
            .navigationTitle(String(localized: "New Event"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Create")) {
                        createEvent()
                    }
                    .disabled(!canCreate)
                }
            }
        }
    }

    private func createEvent() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let trimmedVenue = venueName.trimmingCharacters(in: .whitespaces)
        let venueNames = trimmedVenue.isEmpty ? [] : [trimmedVenue]

        let latitude = Double(latitudeText.trimmingCharacters(in: .whitespaces)) ?? 0
        let longitude = Double(longitudeText.trimmingCharacters(in: .whitespaces)) ?? 0

        let event = EventModel(
            title: trimmedTitle,
            date: date,
            latitude: latitude,
            longitude: longitude,
            venueNames: venueNames
        )
        event.ownerRecordName = CloudKitIdentity.currentUserRecordName
        modelContext.insert(event)

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
