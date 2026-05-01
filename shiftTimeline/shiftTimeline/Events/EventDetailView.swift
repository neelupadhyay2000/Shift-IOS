import SwiftUI
import SwiftData
import CloudKit
import WidgetKit
import Models
import Services

/// Displays the details for a single event.
///
/// Fetched by `id` so the view works correctly whether pushed on iPhone
/// or shown in the iPad detail column.
struct EventDetailView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(WatchSessionManager.self) private var watchSessionManager
    @Environment(LiveActivityManager.self) private var liveActivityManager

    @Query private var results: [EventModel]

    @State private var isShowingShareSheet = false
    @State private var activeShareForSheet: CKShare?
    @State private var isPreparingShare = false
    @State private var shareError: String?
    @State private var paywallTrigger: PaywallTrigger?

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
        event?.isOwnedBy(CloudKitIdentity.shared.currentUserRecordName) ?? true
    }

    /// The VendorModel linked to the current iCloud user, if this is a shared event.
    private var currentVendor: VendorModel? {
        event?.vendorForUser(CloudKitIdentity.shared.currentUserRecordName)
    }

    /// True when the current vendor has an unacknowledged shift with a known delta.
    private var showAcknowledgmentBanner: Bool {
        guard !isOwner, let vendor = currentVendor else { return false }
        return !vendor.hasAcknowledgedLatestShift && vendor.pendingShiftDelta != nil
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
        .sheet(item: $paywallTrigger) { trigger in
            PaywallView(trigger: trigger)
        }
    }

    private func eventContent(_ event: EventModel) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                let atRisk = atRiskOutdoorBlocks(for: event)
                ForEach(Array(atRisk.enumerated()), id: \.offset) { _, item in
                    RainWarningBanner(blockTitle: item.blockTitle, rainProbability: item.probability)
                }
                if showAcknowledgmentBanner, let vendor = currentVendor {
                    ShiftAcknowledgmentBanner(vendor: vendor)
                }
                heroHeader(event)
                quickAccessCards(event)
                locationSection(event)
                tracksSummary(event)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background { WarmBackground() }
        // Re-runs when weatherSnapshot becomes nil (cache busted by block location change)
        // and again when the fresh snapshot is written back. The second run hits the fresh
        // cache immediately and is a no-op.
        .task(id: event.weatherSnapshot) {
            let service = WeatherService()
            _ = await service.fetchIfNeeded(for: event)
            try? modelContext.save()
        }
    }

    /// Returns the list of outdoor blocks with `rainProbability > 0.5` from a fresh snapshot.
    /// Returns an empty array if the snapshot is missing, corrupt, or stale (≥ 30 min old).
    private func atRiskOutdoorBlocks(for event: EventModel) -> [(blockTitle: String, probability: Double)] {
        guard let data = event.weatherSnapshot,
              let snapshot = try? JSONDecoder().decode(WeatherSnapshot.self, from: data),
              snapshot.isFresh else {
            return []
        }
        let allBlocks = (event.tracks ?? [])
            .flatMap { $0.blocks ?? [] }
            .sorted { $0.scheduledStart < $1.scheduledStart }
        let riskEntries = snapshot.atRiskEntries(for: allBlocks.map { (id: $0.id, isOutdoor: $0.isOutdoor) })
        return riskEntries.compactMap { entry in
            guard let block = allBlocks.first(where: { $0.id == entry.blockId }) else { return nil }
            return (blockTitle: block.title, probability: entry.rainProbability)
        }
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
                        .accessibilityHidden(true)
                    Text(event.status.label)
                        .font(.caption)
                        .fontWeight(.bold)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(event.status.tintColor.opacity(0.12), in: Capsule())
                .foregroundStyle(event.status.tintColor)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(event.status.label)
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
                            .accessibilityHidden(true)
                        Text(String(localized: "Go Live"))
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                            .accessibilityHidden(true)
                    }
                    .premiumCard()
                    .background(Color.red, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .simultaneousGesture(TapGesture().onEnded {
                    startLiveMode(for: event)
                })
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Go Live"))
                .accessibilityHint(String(localized: "Starts live event execution mode"))
            }

            HStack(spacing: 12) {
                let blockCount = (event.tracks ?? []).flatMap { $0.blocks ?? [] }.count
                NavigationLink(value: EventDestination.timelineBuilder(eventID: event.id)) {
                    quickCard(
                        icon: "calendar.day.timeline.leading",
                        value: "\(blockCount)",
                        subtitle: String(localized: "timeline_card_label", defaultValue: "Timeline"),
                        color: .blue
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "\(blockCount) timeline blocks"))
                .accessibilityHint(String(localized: "Opens timeline builder"))

                let vendorCount = (event.vendors ?? []).count
                NavigationLink(value: EventDestination.vendorManager(eventID: event.id)) {
                    quickCard(
                        icon: "person.2.fill",
                        value: "\(vendorCount)",
                        subtitle: String(localized: "assigned"),
                        color: .purple
                    )
                }
                .buttonStyle(.plain)
                .disabled(!isOwner)
                .opacity(isOwner ? 1 : 0.5)
                .accessibilityLabel(String(localized: "\(vendorCount) vendors assigned"))
                .accessibilityHint(isOwner ? String(localized: "Opens vendor manager") : String(localized: "Only available to event owner"))
            }

            NavigationLink(value: EventDestination.pdfExport(eventID: event.id)) {
                HStack(spacing: 10) {
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text(String(localized: "Export PDF"))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .premiumCard()
            }
            .buttonStyle(.plain)
            .accessibilityHint(String(localized: "Generates a PDF timeline document"))

            if event.status == .completed {
                NavigationLink(value: EventDestination.postEventReport(eventID: event.id)) {
                    HStack(spacing: 10) {
                        Image(systemName: "chart.bar.doc.horizontal")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.indigo)
                            .accessibilityHidden(true)
                        Text(String(localized: "Export Report"))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .premiumCard()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(AccessibilityID.Report.exportButton)
                .accessibilityLabel(String(localized: "Export Post-Event Report"))
                .accessibilityHint(String(localized: "Generates a post-event summary report"))
            }

            if isOwner {
                shareWithVendorsButton(event)
            }
        }
    }

    private func shareWithVendorsButton(_ event: EventModel) -> some View {
        Button {
            guard SubscriptionManager.shared.isProUser else {
                paywallTrigger = .vendorSharing
                return
            }
            prepareShareSheet(for: event)
        } label: {
            HStack(spacing: 10) {
                if isPreparingShare {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: event.shareURL != nil ? "person.2.badge.gearshape" : "square.and.arrow.up")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
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
                    .accessibilityHidden(true)
            }
            .premiumCard()
        }
        .buttonStyle(.plain)
        .disabled(isPreparingShare)
        .accessibilityHint(isPreparingShare ? String(localized: "Preparing share link, please wait") : "")
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
        .alert("Sharing Error", isPresented: Binding(
            get: { shareError != nil },
            set: { if !$0 { shareError = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            if let shareError {
                Text(shareError)
            }
        }
    }

    /// Prepares a CKShare (creating or fetching as needed) then presents
    /// `UICloudSharingController` via the non-deprecated `init(share:container:)`.
    private func prepareShareSheet(for event: EventModel) {
        // Gate share traffic on mirror health. A degraded mirror means the
        // schema can't reconcile and CKQuery against `CD_EventModel` will
        // never find the record — surface a distinct, actionable error
        // instead of looping the user through "please wait a moment".
        switch CloudKitShareGate.decide(for: PersistenceController.shared.cloudKitMirrorState) {
        case .blockDegradedSync:
            shareError = String(
                localized: "sharing_error_mirror_degraded",
                defaultValue: "Sync is paused because this version of the app is out of date. Please update the app to resume iCloud sync, then try sharing again."
            )
            return
        case .blockCloudKitUnavailable:
            shareError = String(
                localized: "sharing_error_cloudkit_unavailable",
                defaultValue: "iCloud sync is unavailable. Sign in to iCloud in Settings, then try sharing again."
            )
            return
        case .proceed:
            break
        }

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

    /// Creates a new `CKShare` tied to the event's mirrored CloudKit record,
    /// saves it, and presents the sheet.
    ///
    /// Child records (tracks, blocks, vendors) are fetched from CloudKit and
    /// their `parent` field is set before saving. Without this, CloudKit's
    /// hierarchical sharing only delivers the root event record to recipients,
    /// leaving the timeline empty (0 blocks, 0 tracks).
    private func createNewShare(for event: EventModel) {
        fetchEventRootRecord(for: event) { result in
            Task { @MainActor in
                switch result {
                case .success(let rootRecord):
                    let children = await self.fetchChildRecordsForShare(
                        rootRecord: rootRecord,
                        zone: rootRecord.recordID.zoneID
                    )

                    let share = CKShare(rootRecord: rootRecord)
                    share[CKShare.SystemFieldKey.title] = event.title as CKRecordValue
                    share.publicPermission = .readOnly

                    let operation = CKModifyRecordsOperation(
                        recordsToSave: [rootRecord] + children + [share],
                        recordIDsToDelete: nil
                    )
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
                    // Use .changedKeys so CloudKit only writes the `parent` field we set,
                    // preventing a serverRecordChanged conflict if NSPersistentCloudKitContainer
                    // has written to these same records between our fetch and this save.
                    operation.savePolicy = .changedKeys
                    self.cloudKitContainer.privateCloudDatabase.add(operation)

                case .failure(let error):
                    self.isPreparingShare = false
                    self.shareError = error.localizedDescription
                }
            }
        }
    }

    /// Fetches all child records (tracks, blocks, vendors) for a shared event
    /// and sets their CloudKit `parent` field for hierarchical sharing.
    ///
    /// CloudKit's `recordZoneChanges` on the recipient's shared zone only returns
    /// records that have a `parent` chain leading back to the root record.
    /// `NSPersistentCloudKitContainer` uses `CD_event`/`CD_track` reference fields
    /// for Swift relationships but does NOT set the CloudKit-level `parent` field,
    /// so we must set it explicitly here before saving the share.
    private func fetchChildRecordsForShare(
        rootRecord: CKRecord,
        zone: CKRecordZone.ID
    ) async -> [CKRecord] {
        // NSPersistentCloudKitContainer stores relationship fields (CD_event, CD_track)
        // as STRING (the related record's recordName), not as CKRecord.Reference.
        // Using a CKRecord.Reference in the predicate causes:
        //   CKInternalErrorDomain Code=1009 "Field 'CD_event' has a value type of STRING
        //   and cannot be queried using filter value type REFERENCE"
        let eventRecordName = rootRecord.recordID.recordName
        var children: [CKRecord] = []

        let tracks = await queryAllCKRecords(
            type: "CD_TimelineTrack",
            predicate: NSPredicate(format: "CD_event == %@", eventRecordName),
            zone: zone
        )
        for track in tracks {
            // Parent references for CloudKit sharing hierarchy must use .none — using
            // .deleteSelf triggers an NSAssertionHandler abort in iOS 26 (CKRecord.m:2324).
            track.parent = CKRecord.Reference(recordID: rootRecord.recordID, action: .none)
        }
        children.append(contentsOf: tracks)

        let vendors = await queryAllCKRecords(
            type: "CD_VendorModel",
            predicate: NSPredicate(format: "CD_event == %@", eventRecordName),
            zone: zone
        )
        for vendor in vendors {
            vendor.parent = CKRecord.Reference(recordID: rootRecord.recordID, action: .none)
        }
        children.append(contentsOf: vendors)

        for track in tracks {
            let trackRecordName = track.recordID.recordName
            let blocks = await queryAllCKRecords(
                type: "CD_TimeBlockModel",
                predicate: NSPredicate(format: "CD_track == %@", trackRecordName),
                zone: zone
            )
            for block in blocks {
                block.parent = CKRecord.Reference(recordID: track.recordID, action: .none)
            }
            children.append(contentsOf: blocks)
        }

        return children
    }

    /// Pages through a CloudKit query and returns all matching records.
    /// On query failure, returns whatever records were fetched before the error.
    private func queryAllCKRecords(
        type: String,
        predicate: NSPredicate,
        zone: CKRecordZone.ID
    ) async -> [CKRecord] {
        var allRecords: [CKRecord] = []
        var currentCursor: CKQueryOperation.Cursor?

        repeat {
            let page: (records: [CKRecord], cursor: CKQueryOperation.Cursor?) =
                await withCheckedContinuation { continuation in
                    var pageRecords: [CKRecord] = []
                    let op: CKQueryOperation
                    if let cursor = currentCursor {
                        op = CKQueryOperation(cursor: cursor)
                    } else {
                        op = CKQueryOperation(query: CKQuery(recordType: type, predicate: predicate))
                    }
                    op.zoneID = zone
                    op.recordMatchedBlock = { _, result in
                        if case .success(let record) = result { pageRecords.append(record) }
                    }
                    op.queryResultBlock = { result in
                        switch result {
                        case .success(let nextCursor):
                            continuation.resume(returning: (pageRecords, nextCursor))
                        case .failure:
                            continuation.resume(returning: (pageRecords, nil))
                        }
                    }
                    cloudKitContainer.privateCloudDatabase.add(op)
                }
            allRecords.append(contentsOf: page.records)
            currentCursor = page.cursor
        } while currentCursor != nil

        return allRecords
    }

    /// Finds the mirrored CloudKit root record for an event.
    ///
    /// Core Data / SwiftData uses opaque record names, so we must not derive the
    /// `CKRecord.ID` from the model UUID.
    private func fetchEventRootRecord(
        for event: EventModel,
        completion: @escaping (Result<CKRecord, Error>) -> Void
    ) {
        // SwiftData / NSPersistentCloudKitContainer mirrors all records into
        // this custom zone. Querying the default zone returns empty; querying
        // against a container whose schema hasn't been pushed yet surfaces
        // the "Did not find record type" error — we translate that into a
        // user-actionable message below.
        let coreDataZoneID = CKRecordZone.ID(
            zoneName: "com.apple.coredata.cloudkit.zone",
            ownerName: CKCurrentUserDefaultName
        )
        let query = CKQuery(recordType: "CD_EventModel", predicate: NSPredicate(value: true))
        var foundRecord: CKRecord?

        func runQuery(cursor: CKQueryOperation.Cursor? = nil) {
            let operation: CKQueryOperation = if let cursor {
                CKQueryOperation(cursor: cursor)
            } else {
                CKQueryOperation(query: query)
            }
            operation.zoneID = coreDataZoneID

            var pageError: Error?

            operation.recordMatchedBlock = { _, result in
                switch result {
                case .success(let record):
                    let possibleValues: [Any?] = [record["id"], record["CD_id"]]
                    let isMatch = possibleValues.contains { value in
                        if let uuid = value as? UUID {
                            return uuid == event.id
                        }
                        if let string = value as? String {
                            return string == event.id.uuidString
                        }
                        return false
                    }

                    if isMatch {
                        foundRecord = record
                    }

                case .failure(let error):
                    pageError = error
                }
            }

            operation.queryResultBlock = { result in
                switch result {
                case .success(let nextCursor):
                    if let foundRecord {
                        completion(.success(foundRecord))
                    } else if let nextCursor {
                        runQuery(cursor: nextCursor)
                    } else if let pageError {
                        completion(.failure(pageError))
                    } else {
                        completion(.failure(SharingLookupError.eventNotYetSynced))
                    }

                case .failure(let error):
                    // CloudKit returns an "unknown item" error when the record
                    // type hasn't been published yet, and "zoneNotFound" before
                    // the first SwiftData push creates the mirror zone. Treat
                    // both as "not yet synced" rather than a hard failure.
                    if let ckError = error as? CKError,
                       ckError.code == .unknownItem || ckError.code == .zoneNotFound {
                        completion(.failure(SharingLookupError.eventNotYetSynced))
                    } else {
                        completion(.failure(error))
                    }
                }
            }

            cloudKitContainer.privateCloudDatabase.add(operation)
        }

        runQuery()
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
        let rootRecordID = metadata.hierarchicalRootRecordID
        cloudKitContainer.privateCloudDatabase.fetch(withRecordID: shareRecordID) { record, _ in
            Task { @MainActor in
                self.isPreparingShare = false
                if let share = record as? CKShare {
                    // Repair any children that are missing their CloudKit `parent` field.
                    // Shares created before the hierarchical-parent fix had 0 children with
                    // `parent` set, so recipients always received an empty event. Running this
                    // every time the management sheet opens ensures a one-time self-heal.
                    // `hierarchicalRootRecordID` is nil for zone-level shares; skip repair
                    // in that case since there is no nominated root record to re-parent from.
                    if let rootRecordID {
                        Task {
                            await self.refreshChildParentFields(rootRecordID: rootRecordID)
                        }
                    }
                    self.activeShareForSheet = share
                    self.isShowingShareSheet = true
                } else {
                    self.shareError = String(localized: "Could not load share details")
                }
            }
        }
    }

    /// Re-fetches child records and (re-)saves their CloudKit `parent` field.
    ///
    /// Idempotent and non-blocking: called in the background when an existing share
    /// management sheet is opened so that pre-fix shares are silently repaired.
    private func refreshChildParentFields(rootRecordID: CKRecord.ID) async {
        do {
            let rootRecord = try await cloudKitContainer.privateCloudDatabase.record(for: rootRecordID)
            let children = await fetchChildRecordsForShare(
                rootRecord: rootRecord,
                zone: rootRecordID.zoneID
            )
            guard !children.isEmpty else { return }
            let operation = CKModifyRecordsOperation(recordsToSave: children, recordIDsToDelete: nil)
            operation.savePolicy = .changedKeys
            cloudKitContainer.privateCloudDatabase.add(operation)
        } catch {
            // Non-fatal: the share is still valid even if the child refresh fails.
        }
    }

    private enum SharingLookupError: LocalizedError {
        case eventNotYetSynced

        var errorDescription: String? {
            String(localized: "This event hasn't synced to iCloud yet. Please wait a moment and try sharing again.")
        }
    }

    private func startLiveMode(for event: EventModel) {
        let allBlocks = (event.tracks ?? [])
            .flatMap { $0.blocks ?? [] }
            .sorted(by: { $0.scheduledStart < $1.scheduledStart })

        event.status = .live
        event.wentLiveAt = Date()
        AnalyticsService.send(.eventGoLive)
        for block in allBlocks where block.status != .completed {
            block.status = .upcoming
        }
        let activeBlock = allBlocks.first(where: { $0.status != .completed })
        activeBlock?.status = .active

        do {
            try modelContext.save()
            watchSessionManager.sendCurrentContext()
        } catch {
            // Save failed — don't push stale context to Watch.
        }

        // Widgets and Live Activities are Pro-only features. Free users still enter live
        // mode (the core function), but we silently skip the Pro side-effects rather than
        // interrupting their flow with a mid-action paywall. Upsell happens elsewhere.
        guard SubscriptionManager.shared.isProUser else { return }

        // Write initial widget data so the home screen widget updates immediately.
        if let active = activeBlock {
            let nextUp = allBlocks
                .drop(while: { $0.id != active.id })
                .dropFirst()
                .first(where: { $0.status != .completed })

            let data = WidgetSharedData(
                activeBlockTitle: active.title,
                blockEndDate: active.scheduledStart.addingTimeInterval(active.duration),
                nextBlockTitle: nextUp?.title,
                nextBlockStartTime: nextUp?.scheduledStart,
                sunsetTime: event.sunsetTime,
                eventID: event.id,
                eventName: event.title,
                isEventLive: true
            )
            WidgetDataStore.save(data)
            WidgetCenter.shared.reloadTimelines(ofKind: "shiftTimelineWidget")
            WidgetCenter.shared.reloadTimelines(ofKind: "ShiftMediumWidget")

            // Start the Lock Screen / Dynamic Island Live Activity.
            liveActivityManager.start(
                eventTitle: event.title,
                currentBlockTitle: active.title,
                blockEndTime: active.scheduledStart.addingTimeInterval(active.duration),
                nextBlockTitle: nextUp?.title,
                sunsetTime: event.sunsetTime,
                eventID: event.id
            )
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
                .accessibilityHidden(true)
            Text(String(localized: "Sunset"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(time, format: .dateTime.hour().minute())
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Sunset at \(time.formatted(.dateTime.hour().minute()))"))
    }

    private func goldenHourRow(_ time: Date) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "sun.and.horizon.fill")
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)
            Text(String(localized: "Golden Hour"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(time, format: .dateTime.hour().minute())
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Golden hour starts at \(time.formatted(.dateTime.hour().minute()))"))
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
                .accessibilityHidden(true)

            Text(value)
                .font(.title)
                .fontWeight(.bold)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .premiumCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(subtitle)")
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
