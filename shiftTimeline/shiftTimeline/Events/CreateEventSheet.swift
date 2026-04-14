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
        modelContext.insert(event)

        let mainTrack = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true, event: event)
        modelContext.insert(mainTrack)

        // Fire-and-forget sunset fetch when coordinates are provided.
        if latitude != 0, longitude != 0 {
            let eventID = event.id
            let eventDate = date
            Task {
                await fetchSunsetTimes(
                    eventID: eventID,
                    latitude: latitude,
                    longitude: longitude,
                    date: eventDate
                )
            }
        }

        dismiss()
    }

    @MainActor
    private func fetchSunsetTimes(
        eventID: UUID,
        latitude: Double,
        longitude: Double,
        date: Date
    ) async {
        let service = SunsetService()
        do {
            let result = try await service.fetch(
                latitude: latitude,
                longitude: longitude,
                date: date
            )
            let descriptor = FetchDescriptor<EventModel>(
                predicate: #Predicate { $0.id == eventID }
            )
            guard let event = try? modelContext.fetch(descriptor).first else { return }
            event.sunsetTime = result.sunset
            event.goldenHourStart = result.goldenHourStart
        } catch {
            // Sunset fetch is best-effort — event was already created.
        }
    }
}

#Preview {
    CreateEventSheet()
        .modelContainer(try! PersistenceController.forTesting())
}
