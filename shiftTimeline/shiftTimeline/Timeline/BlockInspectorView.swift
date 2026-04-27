import SwiftUI
import SwiftData
import MapKit
import Models
import Services

/// Inspector for editing an existing time block.
///
/// Supports two presentation modes:
/// - **Sheet mode** (`isInspectorMode = false`): Wraps content in `NavigationStack` with
///   Save/Cancel toolbar. Changes are buffered in `@State` and committed on Save.
/// - **Inspector mode** (`isInspectorMode = true`): No `NavigationStack` wrapper.
///   Changes are live-written to the model via `.onChange` — the timeline updates in real-time.
///   Used on iPad where the inspector is a trailing sidebar panel.
struct BlockInspectorView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let block: TimeBlockModel
    let eventID: UUID
    let isInspectorMode: Bool
    let isReadOnly: Bool

    @Query private var eventResults: [EventModel]

    init(block: TimeBlockModel, eventID: UUID, isInspectorMode: Bool = false, isReadOnly: Bool = false) {
        self.block = block
        self.eventID = eventID
        self.isInspectorMode = isInspectorMode
        self.isReadOnly = isReadOnly
        _eventResults = Query(
            filter: #Predicate<EventModel> { $0.id == eventID }
        )
    }

    private var event: EventModel? { eventResults.first }

    /// All vendors belonging to this event.
    private var eventVendors: [VendorModel] {
        event?.vendors ?? []
    }

    /// All sibling blocks in the same event (excluding the current block).
    private var siblingBlocks: [TimeBlockModel] {
        guard let event else { return [] }
        return (event.tracks ?? [])
            .flatMap { $0.blocks ?? [] }
            .filter { $0.id != block.id }
            .sorted { $0.scheduledStart < $1.scheduledStart }
    }

    /// Whether the current user (as a vendor) is assigned to this block.
    /// Owners always see full details. Non-owners only see details if their
    /// linked VendorModel is in this block's vendors list.
    private var canSeeDetails: Bool {
        if !isReadOnly { return true }
        guard let event else { return false }
        guard let currentVendor = event.vendorForUser(CloudKitIdentity.shared.currentUserRecordName) else {
            return false
        }
        return (block.vendors ?? []).contains { $0.id == currentVendor.id }
    }

    // MARK: - State

    @State private var title: String = ""
    @State private var startTime: Date = .now
    @State private var duration: TimeInterval = 1800
    @State private var isPinned: Bool = false
    @State private var notes: String = ""
    @State private var colorTag: String = "#007AFF"
    @State private var icon: String = "circle.fill"
    @State private var selectedVendorIDs: Set<UUID> = []
    @State private var selectedDependencyIDs: Set<UUID> = []
    @State private var isOutdoor: Bool = false
    @State private var venueAddress: String = ""
    @State private var venueName: String = ""
    @State private var blockLatitude: Double = 0
    @State private var blockLongitude: Double = 0
    @State private var startTimePickerID = UUID()
    @State private var startTimePickerTask: Task<Void, Never>?

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Body

    var body: some View {
        if isInspectorMode {
            inspectorBody
        } else {
            sheetBody
        }
    }

    /// iPad inspector panel — no NavigationStack, live-write on change.
    private var inspectorBody: some View {
        inspectorForm
            .formStyle(.grouped)
            .disabled(isReadOnly)
            .onAppear { loadState() }
            .onDisappear {
                startTimePickerTask?.cancel()
                startTimePickerTask = nil
            }
            .onChange(of: block.id) { _, _ in loadState() }
            .onChange(of: blockLatitude) { _, new in
                // Bust weather cache when a block venue location is resolved in inspector mode.
                // Do NOT call modelContext.save() here — the sibling .onChange in
                // InspectorLiveWriteModifier writes `block.blockLatitude` in the same
                // runloop tick. Let SwiftData's autosave coalesce both mutations into
                // a single transaction so Ripple/Weather don't see a half-written state.
                if new != 0, let event {
                    event.weatherSnapshot = nil
                }
            }
            .modifier(InspectorLiveWriteModifier(block: block,
                                                 title: title,
                                                 startTime: startTime,
                                                 duration: duration,
                                                 isPinned: isPinned,
                                                 notes: notes,
                                                 colorTag: colorTag,
                                                 icon: icon,
                                                 isOutdoor: isOutdoor,
                                                 venueAddress: venueAddress,
                                                 venueName: venueName,
                                                 blockLatitude: blockLatitude,
                                                 blockLongitude: blockLongitude,
                                                 eventVendors: eventVendors,
                                                 siblingBlocks: siblingBlocks,
                                                 selectedVendorIDs: selectedVendorIDs,
                                                 selectedDependencyIDs: selectedDependencyIDs))
    }

    private var inspectorForm: some View {
        Form {
            basicInfoSection
            locationSection
            if canSeeDetails {
                detailsSection
                voiceMemoSection
                vendorsSection
                dependenciesSection
            }
        }
    }

    /// iPhone sheet — NavigationStack with Save/Cancel toolbar.
    private var sheetBody: some View {
        NavigationStack {
            Form {
                basicInfoSection
                locationSection
                if canSeeDetails {
                    detailsSection
                    voiceMemoSection
                    vendorsSection
                    dependenciesSection
                }
            }
            .disabled(isReadOnly)
            .navigationTitle(isReadOnly ? String(localized: "Block Details") : String(localized: "Edit Block"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isReadOnly ? String(localized: "Done") : String(localized: "Cancel")) {
                        dismiss()
                    }
                }
                if !isReadOnly {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "Save")) {
                            saveChanges()
                        }
                        .disabled(!canSave)
                    }
                }
            }
        }
        .onAppear { loadState() }
        .onChange(of: block.id) { _, _ in loadState() }
    }

    private func loadState() {
        title = block.title
        startTime = block.scheduledStart
        duration = block.duration
        isPinned = block.isPinned
        notes = block.notes
        colorTag = block.colorTag
        icon = block.icon
        isOutdoor = block.isOutdoor
        venueAddress = block.venueAddress
        venueName = block.venueName
        blockLatitude = block.blockLatitude
        blockLongitude = block.blockLongitude
        selectedVendorIDs = Set((block.vendors ?? []).map(\.id))
        selectedDependencyIDs = Set((block.dependencies ?? []).map(\.id))
    }

    // MARK: - Section 1: Basic Info

    private var basicInfoSection: some View {
        Section(String(localized: "Basic Info")) {
            TextField(String(localized: "Title"), text: $title)
            DatePicker(String(localized: "Start Time"), selection: $startTime, displayedComponents: [.date, .hourAndMinute])
                    .id(startTimePickerID)
                    .onChange(of: startTime) { _, _ in
                        startTimePickerTask?.cancel()
                        startTimePickerTask = Task {
                            try? await Task.sleep(for: .seconds(0.15))
                            guard !Task.isCancelled else { return }
                            startTimePickerID = UUID()
                        }
                    }

            Picker(String(localized: "Duration"), selection: $duration) {
                ForEach(CreateBlockSheet.durationOptions, id: \.1) { label, value in
                    Text(label).tag(value)
                }
            }
            .pickerStyle(.segmented)

            Toggle(String(localized: "Pinned"), isOn: $isPinned)
            Toggle(String(localized: "Outdoor location"), isOn: $isOutdoor)
        }
    }

    // MARK: - Section 2: Venue Location

    private var locationSection: some View {
        Section(String(localized: "Venue Location")) {
            BlockLocationPickerView(
                currentAddress: venueAddress,
                currentVenueName: venueName
            ) { result in
                venueAddress = result.venueAddress
                venueName = result.venueName
                blockLatitude = result.coordinate?.latitude ?? 0
                blockLongitude = result.coordinate?.longitude ?? 0
            }
        }
    }

    // MARK: - Section 3: Details

    private var detailsSection: some View {
        Section(String(localized: "Details")) {
            TextField(String(localized: "Notes"), text: $notes, axis: .vertical)
                .lineLimit(3...6)

            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Color"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    ForEach(Self.colorOptions, id: \.value) { option in
                        Circle()
                            .fill(Color(hex: option.value))
                            .frame(width: 32, height: 32)
                            .overlay {
                                if colorTag == option.value {
                                    Circle()
                                        .strokeBorder(.primary, lineWidth: 2.5)
                                }
                            }
                            .accessibilityLabel(option.label)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityValue(colorTag == option.value ? String(localized: "Selected") : "")
                            .onTapGesture {
                                colorTag = option.value
                            }
                    }
                }
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Icon"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                    ForEach(Self.iconOptions, id: \.systemImage) { option in
                        Image(systemName: option.systemImage)
                            .font(.title3)
                            .frame(width: 40, height: 40)
                            .background(
                                icon == option.systemImage
                                    ? Color.accentColor.opacity(0.2)
                                    : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay {
                                if icon == option.systemImage {
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(Color.accentColor, lineWidth: 2)
                                }
                            }
                            .accessibilityLabel(option.label)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityValue(icon == option.systemImage ? String(localized: "Selected") : "")
                            .onTapGesture {
                                icon = option.systemImage
                            }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Section 4: Voice Memo

    @ViewBuilder
    private var voiceMemoSection: some View {
        if block.voiceMemoURL != nil {
            Section(String(localized: "Voice Memo")) {
                if let resolved = VoiceMemoStorage.resolve(block.voiceMemoURL) {
                    VoiceMemoPlaybackRow(url: resolved) {
                        VoiceMemoStorage.deleteFile(for: block.voiceMemoURL)
                        block.voiceMemoURL = nil
                    }
                } else {
                    HStack {
                        Image(systemName: "icloud.slash")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(String(localized: "Voice memo not yet available on this device"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - Section 5: Vendors

    private var vendorsSection: some View {
        Section(String(localized: "Vendors")) {
            if eventVendors.isEmpty {
                Text(String(localized: "No vendors for this event"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(eventVendors) { vendor in
                    let isSelected = selectedVendorIDs.contains(vendor.id)
                    Button {
                        if isSelected {
                            selectedVendorIDs.remove(vendor.id)
                        } else {
                            selectedVendorIDs.insert(vendor.id)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(vendor.name)
                                Text(vendor.role.rawValue.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .tint(.primary)
                    .accessibilityLabel("\(vendor.name), \(vendor.role.rawValue.capitalized)")
                    .accessibilityValue(isSelected ? String(localized: "Assigned") : String(localized: "Not assigned"))
                }
            }
        }
    }

    // MARK: - Section 6: Dependencies

    private var dependenciesSection: some View {
        Section(String(localized: "Dependencies")) {
            if siblingBlocks.isEmpty {
                Text(String(localized: "No other blocks in this event"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(siblingBlocks) { sibling in
                    let isSelected = selectedDependencyIDs.contains(sibling.id)
                    Button {
                        if isSelected {
                            selectedDependencyIDs.remove(sibling.id)
                        } else {
                            selectedDependencyIDs.insert(sibling.id)
                        }
                    } label: {
                        HStack {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(sibling.isPinned ? Color.red : Color.blue)
                                .frame(width: 4, height: 24)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading) {
                                Text(sibling.title)
                                Text(sibling.scheduledStart, format: .dateTime.hour().minute())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .tint(.primary)
                    .accessibilityLabel("\(sibling.title), \(sibling.scheduledStart.formatted(.dateTime.hour().minute()))")
                    .accessibilityValue(isSelected ? String(localized: "Depends on this block") : String(localized: "No dependency"))
                }
            }
        }
    }

    // MARK: - Save

    private func saveChanges() {
        block.title = title.trimmingCharacters(in: .whitespaces)
        block.scheduledStart = startTime
        block.duration = duration
        block.isPinned = isPinned
        block.notes = notes
        block.colorTag = colorTag
        block.icon = icon

        block.vendors = eventVendors.filter { selectedVendorIDs.contains($0.id) }
        block.dependencies = siblingBlocks.filter { selectedDependencyIDs.contains($0.id) }
        block.isOutdoor = isOutdoor
        block.venueAddress = venueAddress
        block.venueName = venueName
        block.blockLatitude = blockLatitude
        block.blockLongitude = blockLongitude

        // Bust the weather cache so EventDetailView re-fetches with the new location.
        if blockLatitude != 0 || blockLongitude != 0 {
            event?.weatherSnapshot = nil
            try? modelContext.save()
        }

        dismiss()
    }

    // MARK: - Options

    static let colorOptions: [(label: String, value: String)] = [
        ("Blue", "#007AFF"),
        ("Red", "#FF3B30"),
        ("Green", "#34C759"),
        ("Orange", "#FF9500"),
        ("Purple", "#AF52DE"),
        ("Pink", "#FF2D55"),
        ("Yellow", "#FFCC00"),
        ("Gray", "#8E8E93"),
    ]

    static let iconOptions: [(label: String, value: String, systemImage: String)] = [
        ("Ceremony", "ceremony", "heart.fill"),
        ("Dinner", "dinner", "fork.knife"),
        ("Music", "music", "music.note"),
        ("Photo", "photo", "camera.fill"),
        ("Speech", "speech", "mic.fill"),
        ("Travel", "travel", "car.fill"),
        ("Setup", "setup", "wrench.fill"),
        ("People", "people", "person.2.fill"),
        ("Sun", "sun", "sun.max.fill"),
        ("Star", "star", "star.fill"),
        ("Gift", "gift", "gift.fill"),
        ("Custom", "custom", "circle.fill"),
    ]
}

// MARK: - InspectorLiveWriteModifier

/// Breaks the long `.onChange` chain from `BlockInspectorView.inspectorBody`
/// into a dedicated `ViewModifier` so the Swift type-checker can resolve it.
private struct InspectorLiveWriteModifier: ViewModifier {

    let block: TimeBlockModel

    // Basic info
    let title: String
    let startTime: Date
    let duration: TimeInterval
    let isPinned: Bool
    let notes: String
    let colorTag: String
    let icon: String
    let isOutdoor: Bool

    // Location
    let venueAddress: String
    let venueName: String
    let blockLatitude: Double
    let blockLongitude: Double

    // Relationships
    let eventVendors: [VendorModel]
    let siblingBlocks: [TimeBlockModel]
    let selectedVendorIDs: Set<UUID>
    let selectedDependencyIDs: Set<UUID>

    func body(content: Content) -> some View {
        content
            .onChange(of: title) { _, new in block.title = new.trimmingCharacters(in: .whitespaces) }
            .onChange(of: startTime) { _, new in block.scheduledStart = new }
            .onChange(of: duration) { _, new in block.duration = new }
            .onChange(of: isPinned) { _, new in block.isPinned = new }
            .onChange(of: notes) { _, new in block.notes = new }
            .onChange(of: colorTag) { _, new in block.colorTag = new }
            .onChange(of: icon) { _, new in block.icon = new }
            .onChange(of: isOutdoor) { _, new in block.isOutdoor = new }
            .onChange(of: venueAddress) { _, new in block.venueAddress = new }
            .onChange(of: venueName) { _, new in block.venueName = new }
            .onChange(of: blockLatitude) { _, new in block.blockLatitude = new }
            .onChange(of: blockLongitude) { _, new in block.blockLongitude = new }
            .onChange(of: selectedVendorIDs) { _, new in
                block.vendors = eventVendors.filter { new.contains($0.id) }
            }
            .onChange(of: selectedDependencyIDs) { _, new in
                block.dependencies = siblingBlocks.filter { new.contains($0.id) }
            }
    }
}
