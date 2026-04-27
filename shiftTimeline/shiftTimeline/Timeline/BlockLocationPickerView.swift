import SwiftUI
import MapKit

// MARK: - Result Type

/// A resolved venue selection emitted by `BlockLocationPickerView`.
///
/// `coordinate` is `nil` when the user clears the location or when
/// MapKit could not attach a geocoded coordinate to the selection.
/// Callers MUST treat `nil` as "no location" rather than falling
/// back to `(0, 0)`, which is a valid point in the Gulf of Guinea.
struct BlockLocationResult: Equatable {
    let venueName: String
    let venueAddress: String
    let coordinate: CLLocationCoordinate2D?

    static func == (lhs: BlockLocationResult, rhs: BlockLocationResult) -> Bool {
        lhs.venueName == rhs.venueName
            && lhs.venueAddress == rhs.venueAddress
            && lhs.coordinate?.latitude == rhs.coordinate?.latitude
            && lhs.coordinate?.longitude == rhs.coordinate?.longitude
    }
}

// MARK: - Search Completer Bridge

/// Wraps `MKLocalSearchCompleter` as an `@Observable` class so SwiftUI
/// can react to suggestion updates. `MKLocalSearchCompleter` must always
/// be used on the main thread; the `@MainActor` annotation enforces this.
@MainActor
@Observable
final class LocationSearchCompleter: NSObject, MKLocalSearchCompleterDelegate {

    var suggestions: [MKLocalSearchCompletion] = []
    var query: String = "" {
        didSet {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                suggestions = []
                completer.cancel()
            } else {
                completer.queryFragment = query
            }
        }
    }
    var isSearching: Bool = false
    var errorMessage: String?

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.resultTypes = [.address, .pointOfInterest]
        completer.delegate = self
    }

    // MARK: MKLocalSearchCompleterDelegate

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor in
            self.suggestions = results
            self.errorMessage = nil
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            // MKError.loadingThrottled (-1) fires during rapid typing — suppress it.
            let nsError = error as NSError
            if nsError.domain == MKError.errorDomain, nsError.code == MKError.loadingThrottled.rawValue {
                return
            }
            self.errorMessage = error.localizedDescription
        }
    }

    /// Resolves a completion into a `BlockLocationResult` by performing a
    /// one-item `MKLocalSearch`. Returns `nil` on failure.
    func resolve(_ completion: MKLocalSearchCompletion) async -> BlockLocationResult? {
        isSearching = true
        defer { isSearching = false }

        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)

        do {
            let response = try await search.start()
            guard let item = response.mapItems.first else { return nil }
            let coord = item.placemark.coordinate
            let address = [
                item.placemark.subThoroughfare,
                item.placemark.thoroughfare,
                item.placemark.locality,
                item.placemark.administrativeArea,
            ]
            .compactMap { $0 }
            .joined(separator: " ")

            return BlockLocationResult(
                venueName: item.name ?? completion.title,
                venueAddress: address.isEmpty ? completion.subtitle : address,
                coordinate: coord
            )
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}

// MARK: - BlockLocationPickerView

/// A search field + live-updating suggestions list for picking a block venue.
///
/// Usage:
/// ```swift
/// BlockLocationPickerView(
///     currentAddress: block.venueAddress,
///     currentVenueName: block.venueName
/// ) { result in
///     block.venueAddress = result.venueAddress
///     block.venueName = result.venueName
///     block.blockLatitude = result.coordinate?.latitude ?? 0
///     block.blockLongitude = result.coordinate?.longitude ?? 0
/// }
/// ```
struct BlockLocationPickerView: View {

    let currentAddress: String
    let currentVenueName: String
    let onSelect: (BlockLocationResult) -> Void

    @State private var completer = LocationSearchCompleter()
    @State private var searchText: String = ""
    @State private var isEditing = false
    @FocusState private var isFocused: Bool

    private var displayLabel: String {
        if !currentVenueName.isEmpty {
            return currentVenueName
        } else if !currentAddress.isEmpty {
            return currentAddress
        }
        return ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Search field row
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 16))

                if isEditing {
                    TextField(String(localized: "Search address or venue…"), text: $searchText)
                        .focused($isFocused)
                        .autocorrectionDisabled()
                        .onChange(of: searchText) { _, new in
                            completer.query = new
                        }
                } else {
                    Button {
                        searchText = ""
                        isEditing = true
                        isFocused = true
                    } label: {
                        if displayLabel.isEmpty {
                            Text(String(localized: "Add venue location…"))
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 2) {
                                if !currentVenueName.isEmpty {
                                    Text(currentVenueName)
                                        .foregroundStyle(.primary)
                                }
                                if !currentAddress.isEmpty {
                                    Text(currentAddress)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                if completer.isSearching {
                    ProgressView()
                        .controlSize(.small)
                } else if isEditing {
                    Button(String(localized: "Cancel")) {
                        cancelEditing()
                    }
                    .font(.subheadline)
                } else if !displayLabel.isEmpty {
                    Button {
                        clearLocation()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)

            // Suggestions list — shown when searching
            if isEditing && !completer.suggestions.isEmpty {
                Divider().padding(.top, 4)

                ForEach(completer.suggestions, id: \.self) { suggestion in
                    Button {
                        selectSuggestion(suggestion)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.title)
                                .foregroundStyle(.primary)
                                .font(.subheadline)
                            if !suggestion.subtitle.isEmpty {
                                Text(suggestion.subtitle)
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }

            if let error = completer.errorMessage, isEditing {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 4)
            }
        }
    }

    private func selectSuggestion(_ suggestion: MKLocalSearchCompletion) {
        Task {
            guard let result = await completer.resolve(suggestion) else { return }
            onSelect(result)
            cancelEditing()
        }
    }

    private func cancelEditing() {
        searchText = ""
        completer.query = ""
        isEditing = false
        isFocused = false
    }

    private func clearLocation() {
        onSelect(BlockLocationResult(
            venueName: "",
            venueAddress: "",
            coordinate: nil
        ))
    }
}
