import SwiftUI
import SwiftData
import Models

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

    let block: TimeBlockModel
    let eventID: UUID
    let isInspectorMode: Bool

    @Query private var eventResults: [EventModel]

    init(block: TimeBlockModel, eventID: UUID, isInspectorMode: Bool = false) {
        self.block = block
        self.eventID = eventID
        self.isInspectorMode = isInspectorMode
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
        Form {
            basicInfoSection
            detailsSection
            vendorsSection
            dependenciesSection
        }
        .formStyle(.grouped)
        .onAppear { loadState() }
        .onDisappear {
            startTimePickerTask?.cancel()
            startTimePickerTask = nil
        }
        .onChange(of: block.id) { _, _ in loadState() }
        .onChange(of: title) { _, new in block.title = new.trimmingCharacters(in: .whitespaces) }
        .onChange(of: startTime) { _, new in block.scheduledStart = new }
        .onChange(of: duration) { _, new in block.duration = new }
        .onChange(of: isPinned) { _, new in block.isPinned = new }
        .onChange(of: notes) { _, new in block.notes = new }
        .onChange(of: colorTag) { _, new in block.colorTag = new }
        .onChange(of: icon) { _, new in block.icon = new }
        .onChange(of: selectedVendorIDs) { _, new in
            block.vendors = eventVendors.filter { new.contains($0.id) }
        }
        .onChange(of: selectedDependencyIDs) { _, new in
            block.dependencies = siblingBlocks.filter { new.contains($0.id) }
        }
    }

    /// iPhone sheet — NavigationStack with Save/Cancel toolbar.
    private var sheetBody: some View {
        NavigationStack {
            Form {
                basicInfoSection
                detailsSection
                vendorsSection
                dependenciesSection
            }
            .navigationTitle(String(localized: "Edit Block"))
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
        }
    }

    // MARK: - Section 2: Details

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
                            .onTapGesture {
                                icon = option.systemImage
                            }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Section 3: Vendors

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
                            }
                        }
                    }
                    .tint(.primary)
                }
            }
        }
    }

    // MARK: - Section 4: Dependencies

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
                            }
                        }
                    }
                    .tint(.primary)
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
