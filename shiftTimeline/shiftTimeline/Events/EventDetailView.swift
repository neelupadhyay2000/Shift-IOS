import SwiftUI
import SwiftData
import CloudKit
import Models
import Services

/// Displays the details for a single event.
///
/// Fetched by `id` so the view works correctly whether pushed on iPhone
/// or shown in the iPad detail column.
struct EventDetailView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(WatchSessionManager.self) private var watchSessionManager

    @Query private var results: [EventModel]

    @State private var isShowingShareSheet = false
    @State private var activeShareForSheet: CKShare?
    @State private var isPreparingShare = false
    @State private var shareError: String?

    private let cloudKitContainer = CKContainer(identifier: "iCloud.com.neelsoftwaresolutions.shiftTimeline")
    private let eventID: UUID

    init(eventID: UUID) {
        self.eventID = eventID
        _results = Query(
            filter: #Predicate<EventModel> { $0.id == eventID }
        )
    }

    private var event: EventModel? { results.first }

    private var isOwner: Bool {
        event?.isOwnedBy(CloudKitIdentity.currentUserRecordName) ?? true
    }

    var body: some View {
        Group {
            if let event {
                eventContent(event)
            } else {
                ContentUnavailableView(
                    String(localized: "Event Not Found"),
                    systemImage: "exclamationmark.triangle"
                )
            }
        }
        .navigationTitle(event?.title ?? String(localized: "Event"))
        .navigationBarTitleDisplayMode(.large)
    }

    private func eventContent(_ event: EventModel) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                heroHeader(event)
                quickAccessCards(event)
                locationSection(event)
                tracksSummary(event)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background { WarmBackground() }
    }

    private func heroHeader(_ event: EventModel) -> some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.date, format: .dateTime.weekday(.wide).month(.wide).day().year())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if !event.venueNames.isEmpty {
                        Label(event.venueNames.joined(separator: ", "), systemImage: "mappin.and.ellipse")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(event.status.tintColor)
                        .frame(width: 7, height: 7)
                    Text(event.status.label)
                        .font(.caption)
                        .fontWeight(.bold)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(event.status.tintColor.opacity(0.12), in: Capsule())
                .foregroundStyle(event.status.tintColor)
            }
        }
        .premiumCard()
    }

    private func quickAccessCards(_ event: EventModel) -> some View {
        VStack(spacing: 12) {
            if isOwner {
                NavigationLink(value: EventDestination.liveDashboard(eventID: event.id)) {
                    HStack(spacing: 10) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(String(localized: "Go Live"))
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .premiumCard()
                    .background(Color.red, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .simultaneousGesture(TapGesture().onEnded {
                    startLiveMode(for: event)
                })
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                NavigationLink(value: EventDestination.timelineBuilder(eventID: event.id)) {
                    quickCard(
                        icon: "calendar.day.timeline.leading",
                        value: "\((event.tracks ?? []).flatMap { $0.blocks ?? [] }.count)",
                        subtitle: String(localized: "blocks_count_label", defaultValue: "blocks"),
                        color: .blue
                    )
                }
                .buttonStyle(.plain)

                NavigationLink(value: EventDestination.vendorManager(eventID: event.id)) {
                    quickCard(
                        icon: "person.2.fill",
                        value: "\((event.vendors ?? []).count)",
                        subtitle: String(localized: "assigned"),
                        color: .purple
                    )
                }
                .buttonStyle(.plain)
                .disabled(!isOwner)
                .opacity(isOwner ? 1 : 0.5)
            }

            NavigationLink(value: EventDestination.pdfExport(eventID: event.id)) {
                HStack(spacing: 10) {
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text(String(localized: "Export PDF"))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .premiumCard()
            }
            .buttonStyle(.plain)

            if isOwner {
                shareWithVendorsButton(event)
            }
        }
    }

    private func shareWithVendorsButton(_ event: EventModel) -> some View {
        Button {
            prepareShareSheet(for: event)
        } label: {
            HStack(spacing: 10) {
                if isPreparingShare {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: event.shareURL != nil ? "person.2.badge.gearshape" : "square.and.arrow.up")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.green)
                }
                Text(event.shareURL != nil
                     ? String(localized: "Manage Vendor Sharing")
                     : String(localized: "Share with Vendors"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .premiumCard()
        }
        .buttonStyle(.plain)
        .disabled(isPreparingShare)
        .sheet(isPresented: $isShowingShareSheet) {
            if let share = activeShareForSheet {
                CloudSharingView(
                    share: share,
                    container: cloudKitContainer,
                    eventTitle: event.title,
                    onShareSaved: { savedShare in
                        if let url = savedShare.url {
                            event.shareURL = url.absoluteString
                            try? modelContext.save()
                        }
                    },
                    onShareStopped: {
                        event.shareURL = nil
                        activeShareForSheet = nil
                        try? modelContext.save()
                    },
                    onError: { error in
                        shareError = error.localizedDescription
                    }
                )
            }
        }
    }

    /// Prepares a CKShare (creating or fetching as needed) then presents
    /// `UICloudSharingController` via the non-deprecated `init(share:container:)`.
    private func prepareShareSheet(for event: EventModel) {
        isPreparingShare = true

        if let shareURLString = event.shareURL,
           let shareURL = URL(string: shareURLString) {
            // Existing share — fetch it from CloudKit for management.
            fetchExistingShare(at: shareURL, for: event)
        } else {
            // No share yet — create one, save it, then present.
            createNewShare(for: event)
        }
    }

    /// Creates a new `CKShare`, saves it to CloudKit, persists the URL, and presents the sheet.
    private func createNewShare(for event: EventModel) {
        let share = CKShare(recordZoneID: .default)
        share[CKShare.SystemFieldKey.title] = event.title as CKRecordValue
        share.publicPermission = .readOnly

        let operation = CKModifyRecordsOperation(recordsToSave: [share], recordIDsToDelete: nil)
        operation.modifyRecordsResultBlock = { result in
            Task { @MainActor in
                self.isPreparingShare = false
                switch result {
                case .success:
                    event.shareURL = share.url?.absoluteString
                    try? self.modelContext.save()
                    self.activeShareForSheet = share
                    self.isShowingShareSheet = true
                case .failure(let error):
                    self.shareError = error.localizedDescription
                }
            }
        }
        cloudKitContainer.privateCloudDatabase.add(operation)
    }

    /// Fetches an existing `CKShare` by its URL and presents the management sheet.
    private func fetchExistingShare(at shareURL: URL, for event: EventModel) {
        let metadataOperation = CKFetchShareMetadataOperation(shareURLs: [shareURL])
        metadataOperation.perShareMetadataResultBlock = { _, result in
            Task { @MainActor in
                switch result {
                case .success(let metadata):
                    self.resolveShare(from: metadata)
                case .failure:
                    // Share may have been deleted externally — clear stale URL and create fresh.
                    event.shareURL = nil
                    try? self.modelContext.save()
                    self.createNewShare(for: event)
                }
            }
        }
        cloudKitContainer.add(metadataOperation)
    }

    private func resolveShare(from metadata: CKShare.Metadata) {
        let shareRecordID = metadata.share.recordID
        cloudKitContainer.sharedCloudDatabase.fetch(withRecordID: shareRecordID) { record, _ in
            Task { @MainActor in
                self.isPreparingShare = false
                if let share = record as? CKShare {
                    self.activeShareForSheet = share
                    self.isShowingShareSheet = true
                } else {
                    self.shareError = String(localized: "Could not load share details")
                }
            }
        }
    }

    private func startLiveMode(for event: EventModel) {
        let allBlocks = (event.tracks ?? [])
            .flatMap { $0.blocks ?? [] }
            .sorted(by: { $0.scheduledStart < $1.scheduledStart })

        event.status = .live
        for block in allBlocks where block.status != .completed {
            block.status = .upcoming
        }
        allBlocks.first(where: { $0.status != .completed })?.status = .active

        do {
            try modelContext.save()
            watchSessionManager.sendCurrentContext()
        } catch {
            // Save failed — don't push stale context to Watch.
        }
    }

    @ViewBuilder
    private func locationSection(_ event: EventModel) -> some View {
        if event.latitude != 0 || event.longitude != 0 {
            VStack(alignment: .leading, spacing: 10) {
                Label(String(localized: "Location"), systemImage: "location.fill")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    locationItem(label: String(localized: "Lat"), value: String(format: "%.4f", event.latitude))
                    locationItem(label: String(localized: "Lon"), value: String(format: "%.4f", event.longitude))
                }

                if let sunset = event.sunsetTime {
                    sunsetRow(sunset)
                }
                if let golden = event.goldenHourStart {
                    goldenHourRow(golden)
                }
            }
            .premiumCard()
        }
    }

    private func sunsetRow(_ time: Date) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "sunset.fill")
                .foregroundStyle(.orange)
            Text(String(localized: "Sunset"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(time, format: .dateTime.hour().minute())
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }

    private func goldenHourRow(_ time: Date) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "sun.and.horizon.fill")
                .foregroundStyle(.yellow)
            Text(String(localized: "Golden Hour"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(time, format: .dateTime.hour().minute())
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }

    private func tracksSummary(_ event: EventModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(String(localized: "Tracks"), systemImage: "rectangle.stack.fill")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)

            ForEach((event.tracks ?? []).sorted(by: { $0.sortOrder < $1.sortOrder }), id: \TimelineTrack.id) { track in
                trackRow(track)
            }
        }
        .premiumCard()
    }

    private func trackRow(_ track: TimelineTrack) -> some View {
        HStack {
            Text(track.name)
                .font(.subheadline)
                .fontWeight(.medium)
            if track.isDefault {
                Text(String(localized: "Default"))
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                    .foregroundStyle(Color.accentColor)
            }
            Spacer()
            Text("\((track.blocks ?? []).count) blocks")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func quickCard(icon: String, value: String, subtitle: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(color)
                .symbolEffect(.bounce, options: .nonRepeating, value: true)

            Text(value)
                .font(.title)
                .fontWeight(.bold)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .premiumCard()
    }

    private func locationItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .monospacedDigit()
        }
    }
}

// MARK: - EventStatus helpers used by EventRowView are reused here via the extension in EventRowView.swift
