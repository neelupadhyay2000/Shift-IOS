import MapKit
import Models
import Services
import SwiftData
import SwiftUI
import WidgetKit

/// Displays the details for a single event.
///
/// Fetched by `id` so the view works correctly whether pushed on iPhone
/// or shown in the iPad detail column.
///
/// Layout: a large title on the canvas, then a single **summary card** (date +
/// countdown, location with a map thumbnail, a sun chip), the one loud primary
/// action, and grouped **Management** / **Reports** cards of list rows. Secondary
/// utilities (Edit, Save as Template) live in the toolbar's overflow menu so the
/// body stays short and scannable.
struct EventDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(WatchSessionManager.self) private var watchSessionManager
    @Environment(LiveActivityManager.self) private var liveActivityManager
    @Environment(SupabaseAuthService.self) private var authService
    @Environment(DemoSession.self) private var demoSession
    @Environment(\.scenePhase) private var scenePhase
    /// The cutover's shared echo suppressor — non-nil only when the
    /// sync stack is live. Handed to the realtime applier so the planner's own
    /// writes (now flushed to Supabase) aren't re-applied as echoes.
    @Environment(\.realtimeEchoSuppressor) private var echoSuppressor
    @Environment(\.eventRepository) private var injectedEventRepo

    /// Routes the go-live mutation through the Outbox so it syncs to shared
    /// vendors (a bare `modelContext.save()` would stay local).
    private var eventRepo: any EventRepositing {
        injectedEventRepo ?? SwiftDataEventRepository(context: modelContext)
    }

    @Query private var results: [EventModel]

    @State private var paywallTrigger: PaywallTrigger?
    @State private var isShowingEditSheet = false
    @State private var isShowingSaveAsTemplate = false
    @State private var isShowingVendorSharing = false
    @State private var isShowingReviewVendors = false
    @State private var isShowingSignIn = false
    /// Set when sign-in was prompted by a share attempt, so the share flow
    /// resumes automatically once the sign-in sheet dismisses.
    @State private var pendingShareAfterSignIn = false
    /// Drives the per-event Supabase Realtime channel while signed in and viewing
    /// an event — a vendor's shared timeline or the planner watching
    /// vendor acknowledgments land in the ack grid. Lazily created.
    @State private var realtime: RealtimeLifecycleManager?

    private let eventID: UUID

    init(eventID: UUID) {
        self.eventID = eventID
        _results = Query(
            filter: #Predicate<EventModel> { $0.id == eventID }
        )
    }

    private var event: EventModel? {
        results.first
    }

    private var isOwner: Bool {
        EventAccess.isOwner(ownerId: event?.ownerId, currentProfileID: authService.currentProfileID)
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
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $paywallTrigger) { trigger in
            PaywallView(trigger: trigger)
        }
        .sheet(isPresented: $isShowingEditSheet) {
            if let event {
                EditEventSheet(event: event)
            }
        }
        .sheet(isPresented: $isShowingSaveAsTemplate) {
            if let event {
                SaveAsTemplateSheet(event: event)
            }
        }
        .sheet(isPresented: $isShowingSignIn, onDismiss: resumeShareAfterSignIn) {
            SignInView()
        }
        .sheet(isPresented: $isShowingReviewVendors) {
            ReviewVendorsSheet(eventID: eventID)
        }
        .sheet(isPresented: $isShowingVendorSharing) {
            NavigationStack {
                VendorSharingView(eventID: eventID)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(String(localized: "Done")) { isShowingVendorSharing = false }
                        }
                    }
            }
        }
        .onAppear { configureRealtime() }
        .onChange(of: authService.currentProfileID) { _, _ in configureRealtime() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                realtime?.didEnterForeground()
            } else {
                realtime?.didEnterBackground()
            }
        }
        .onDisappear { realtime?.setActiveEvent(nil) }
    }

    // MARK: - Sharing flow

    /// Presents vendor sharing, gating behind the Pro paywall first.
    /// Shared by the signed-in button tap and the post-sign-in continuation.
    private func presentVendorSharing() {
        guard SubscriptionManager.shared.isProUser else {
            paywallTrigger = .vendorSharing
            return
        }
        isShowingVendorSharing = true
    }

    /// Called when the sign-in sheet dismisses. Resumes the share attempt only
    /// if it was triggered by one and the user actually signed in (not cancelled).
    private func resumeShareAfterSignIn() {
        guard pendingShareAfterSignIn else { return }
        pendingShareAfterSignIn = false
        guard authService.isAuthenticated else { return }
        presentVendorSharing()
    }

    // MARK: - Realtime

    /// Subscribes to the event's Supabase Realtime channel while signed in and
    /// viewing the event, so remote changes appear live without a manual refresh
    /// (the `RealtimeChangeApplier` writes into the shared `modelContext`, which
    /// `@Query` reflects). Serves both a vendor watching a shared timeline
    /// and the planner watching vendor acknowledgments land in the ack
    /// grid. Signed-out / local-only use is not streamed.
    ///
    /// The shared `RealtimeEchoSuppressor` is injected from the
    /// environment and passed to the applier, so the planner's own writes — now
    /// flushed to Supabase via the Outbox — aren't re-applied here as echoes.
    private func configureRealtime() {
        guard FeatureFlags.supabaseSync, authService.currentProfileID != nil else {
            realtime?.setActiveEvent(nil)
            return
        }
        if realtime == nil {
            let client = SupabaseClientProvider.shared.client
            realtime = RealtimeLifecycleManager(
                service: RealtimeSyncService(client: client),
                applier: RealtimeChangeApplier(context: modelContext, echoSuppressor: echoSuppressor),
                isForeground: scenePhase == .active
            )
        }
        realtime?.setActiveEvent(eventID)
    }

    private func eventContent(_ event: EventModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                let atRisk = atRiskOutdoorBlocks(for: event)
                ForEach(Array(atRisk.enumerated()), id: \.offset) { _, item in
                    RainWarningBanner(blockTitle: item.blockTitle, rainProbability: item.probability)
                }
                titleHeader(event)
                summaryCard(event)
                primaryAction(event)
                managementSection(event)
                reportsSection(event)
                if eventUsesWeather(event) {
                    // WeatherKit attribution (Guideline 5.2.5): the Apple Weather
                    // mark + legal data-sources link, kept visible (this is a
                    // pushed view, so there's no floating tab bar burying it).
                    WeatherAttributionView()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background { ProBackground() }
        .toolbar {
            if isOwner {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { isShowingEditSheet = true } label: {
                            Label(String(localized: "Edit Event"), systemImage: "pencil")
                        }
                        Button { isShowingSaveAsTemplate = true } label: {
                            Label(String(localized: "Save as Template"), systemImage: "rectangle.stack.badge.plus")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel(String(localized: "More"))
                }
            }
        }
        // Re-runs when weatherSnapshot becomes nil (cache busted by block location change)
        // and again when the fresh snapshot is written back. The second run hits the fresh
        // cache immediately and is a no-op.
        .task(id: event.weatherSnapshot) {
            let service = WeatherService()
            _ = await service.fetchIfNeeded(for: event)
            try? modelContext.save()
        }
        // Re-runs when sunsetTime becomes nil (cache busted by EditEventSheet on date/location
        // change). Ensures golden-hour and sunset data is populated before the user goes live.
        .task(id: event.sunsetTime) {
            let service = SunsetService()
            _ = await service.fetchIfNeeded(for: event)
            try? modelContext.save()
        }
    }

    /// Whether this event queries WeatherKit (has event- or block-level
    /// coordinates), and therefore must display Apple Weather attribution.
    private func eventUsesWeather(_ event: EventModel) -> Bool {
        if event.latitude != 0 || event.longitude != 0 { return true }
        return (event.tracks ?? [])
            .flatMap { $0.blocks ?? [] }
            .contains { $0.blockLatitude != 0 || $0.blockLongitude != 0 }
    }

    /// Returns the list of outdoor blocks with `rainProbability > 0.5` from a fresh snapshot.
    /// Returns an empty array if the snapshot is missing, corrupt, or stale (≥ 30 min old).
    private func atRiskOutdoorBlocks(for event: EventModel) -> [(blockTitle: String, probability: Double)] {
        guard let data = event.weatherSnapshot,
              let snapshot = try? JSONDecoder().decode(WeatherSnapshot.self, from: data),
              snapshot.isFresh
        else {
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

    // MARK: - Title

    private func titleHeader(_ event: EventModel) -> some View {
        Text(event.title)
            .font(.largeTitle.weight(.bold))
            .lineLimit(3)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Summary card (date · countdown · location · sun)

    private func summaryCard(_ event: EventModel) -> some View {
        let venue = event.venueNames.joined(separator: ", ")
        let hasCoords = event.latitude != 0 || event.longitude != 0

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(event.date.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    Circle()
                        .fill(event.status.tintColor)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    Text(EventCountdown.label(for: event.date))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(event.date.formatted(.dateTime.month(.wide).day().year())), \(event.status.label), \(EventCountdown.label(for: event.date))")

            if !venue.isEmpty || hasCoords {
                HStack(spacing: 12) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(venue.isEmpty ? String(localized: "Location pinned") : venue)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    if hasCoords {
                        mapThumbnail(latitude: event.latitude, longitude: event.longitude)
                    }
                }
            }

            if let sunset = event.sunsetTime {
                sunChip(sunset: sunset, golden: event.goldenHourStart)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .proCard()
    }

    /// Non-interactive map preview of the venue — the "sleek" touch from the
    /// reference. Only shown when the event has resolved coordinates.
    private func mapThumbnail(latitude: Double, longitude: Double) -> some View {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            latitudinalMeters: 1200,
            longitudinalMeters: 1200
        )
        return Map(initialPosition: .region(region))
            .frame(width: 76, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Sun/time-of-day chip — the only place the warm accent appears.
    private func sunChip(sunset: Date, golden: Date?) -> some View {
        var text = String(localized: "Sunset \(sunset.formatted(.dateTime.hour().minute()))")
        if let golden {
            text += "  •  " + String(localized: "Golden \(golden.formatted(.dateTime.hour().minute()))")
        }
        return HStack(spacing: 6) {
            Image(systemName: "sun.max.fill").font(.caption2)
            Text(text).font(.footnote.weight(.medium))
        }
        .foregroundStyle(ShiftPalette.warm)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(ShiftPalette.soft(ShiftPalette.warm), in: Capsule())
        .accessibilityElement(children: .combine)
    }

    // MARK: - Primary action (Go Live / View Live — the one loud element)

    @ViewBuilder
    private func primaryAction(_ event: EventModel) -> some View {
        if isOwner {
            NavigationLink(value: EventDestination.liveDashboard(eventID: event.id)) {
                Text(String(localized: "Go Live"))
            }
            .simultaneousGesture(TapGesture().onEnded { startLiveMode(for: event) })
            .buttonStyle(.shiftFilled)
            .accessibilityIdentifier(AccessibilityID.EventDetail.goLiveButton)
            .accessibilityLabel(String(localized: "Go Live"))
            .accessibilityHint(String(localized: "Starts live event execution mode"))
        } else if event.status == .live {
            // Vendor on a shared event that's currently live → read-only live view.
            NavigationLink(value: EventDestination.liveDashboard(eventID: event.id)) {
                Text(String(localized: "View Live"))
            }
            .buttonStyle(.shiftFilled)
            .accessibilityLabel(String(localized: "View Live"))
            .accessibilityHint(String(localized: "Opens the live timeline"))
        }
    }

    // MARK: - Management (Timeline · Vendors · Share)

    private func managementSection(_ event: EventModel) -> some View {
        let allBlocks = (event.tracks ?? []).flatMap { $0.blocks ?? [] }
        let blockCount = allBlocks.count
        let trackCount = (event.tracks ?? []).count
        let assignedToMe = allBlocks.filter { $0.isAssigned(to: authService.currentProfileID) }.count

        return VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Management")).microLabel()

            VStack(spacing: 0) {
                NavigationLink(value: EventDestination.timelineBuilder(eventID: event.id)) {
                    navRow(
                        icon: "calendar",
                        title: String(localized: "Timeline"),
                        subtitle: isOwner
                            ? String(localized: "\(blockCount) Blocks • \(trackCount) Tracks")
                            : String(localized: "\(assignedToMe) assigned to you")
                    )
                }
                .buttonStyle(.pressableCard)
                .accessibilityIdentifier(AccessibilityID.EventDetail.timelineButton)
                .accessibilityHint(String(localized: "Opens timeline builder"))

                if isOwner {
                    rowDivider
                    NavigationLink(value: EventDestination.vendorManager(eventID: event.id)) {
                        navRow(
                            icon: "person.2.fill",
                            title: String(localized: "Vendors"),
                            subtitle: vendorSubtitle(event.vendors ?? [])
                        )
                    }
                    .buttonStyle(.pressableCard)
                    .accessibilityIdentifier(AccessibilityID.EventDetail.vendorsButton)
                    .accessibilityHint(String(localized: "Opens vendor manager"))

                    if FeatureFlags.supabaseSync {
                        rowDivider
                        // Demo mode has no session but is fully local — let the
                        // reviewer open the vendor-invite (iMessage) flow, which
                        // composes entirely on-device, instead of dead-ending on
                        // the sign-in lock they can't satisfy.
                        if authService.isAuthenticated || demoSession.isActive {
                            Button { presentVendorSharing() } label: {
                                navRow(
                                    icon: "square.and.arrow.up",
                                    title: String(localized: "Share with Vendors"),
                                    subtitle: String(localized: "Invite vendors to this event")
                                )
                            }
                            .buttonStyle(.pressableCard)
                            .accessibilityIdentifier(AccessibilityID.EventDetail.shareButton)
                        } else {
                            Button {
                                pendingShareAfterSignIn = true
                                isShowingSignIn = true
                            } label: {
                                navRow(
                                    icon: "square.and.arrow.up",
                                    title: String(localized: "Share with Vendors"),
                                    subtitle: String(localized: "Sign in to invite vendors"),
                                    accessory: "lock.fill"
                                )
                            }
                            .buttonStyle(.pressableCard)
                            .accessibilityIdentifier(AccessibilityID.EventDetail.shareButton)
                            .accessibilityLabel(String(localized: "Share with Vendors — sign in required"))
                        }
                    }
                }
            }
            .proCard(padding: 0)
        }
    }

    /// "12 Accepted • 2 Pending" style summary of the event's vendor invites.
    private func vendorSubtitle(_ vendors: [VendorModel]) -> String {
        guard !vendors.isEmpty else { return String(localized: "No vendors yet") }
        let accepted = vendors.filter {
            VendorInviteStatus.of(invitedAt: $0.invitedAt, profileId: $0.profileId?.uuidString) == .accepted
        }.count
        let pending = vendors.filter {
            VendorInviteStatus.of(invitedAt: $0.invitedAt, profileId: $0.profileId?.uuidString) == .invited
        }.count
        if accepted + pending > 0 {
            return String(localized: "\(accepted) Accepted • \(pending) Pending")
        }
        return String(localized: "\(vendors.count) added")
    }

    // MARK: - Reports (Export PDF · Post-Event Report · Reviews)

    private func reportsSection(_ event: EventModel) -> some View {
        let isCompleted = event.status == .completed

        return VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Reports")).microLabel()

            VStack(spacing: 0) {
                NavigationLink(value: EventDestination.pdfExport(eventID: event.id)) {
                    navRow(
                        icon: "doc.richtext.fill",
                        title: String(localized: "Export PDF"),
                        subtitle: String(localized: "Full run-of-show")
                    )
                }
                .buttonStyle(.pressableCard)
                .accessibilityHint(String(localized: "Generates a PDF timeline document"))

                rowDivider
                if isCompleted {
                    NavigationLink(value: EventDestination.postEventReport(eventID: event.id)) {
                        navRow(
                            icon: "chart.bar.doc.horizontal.fill",
                            title: String(localized: "Post-Event Report"),
                            subtitle: String(localized: "Export the run summary")
                        )
                    }
                    .buttonStyle(.pressableCard)
                    .accessibilityIdentifier(AccessibilityID.Report.exportButton)
                    .accessibilityLabel(String(localized: "Export Post-Event Report"))
                    .accessibilityHint(String(localized: "Generates a post-event summary report"))
                } else {
                    // Shown but inert until the event is completed — mirrors the
                    // reference's "Drafting available after live" affordance.
                    navRow(
                        icon: "chart.bar.doc.horizontal",
                        title: String(localized: "Post-Event Report"),
                        subtitle: String(localized: "Drafting available after live"),
                        accessory: "lock.fill"
                    )
                    .opacity(0.5)
                    .accessibilityLabel(String(localized: "Post-Event Report, available after the event"))
                }

                if isCompleted, isOwner, FeatureFlags.supabaseSync {
                    rowDivider
                    Button { isShowingReviewVendors = true } label: {
                        navRow(
                            icon: "star.bubble.fill",
                            title: String(localized: "Review your vendors"),
                            subtitle: String(localized: "Rate vendors who worked")
                        )
                    }
                    .buttonStyle(.pressableCard)
                    .accessibilityHint(String(localized: "Leave a review for each vendor who worked this event"))
                }
            }
            .proCard(padding: 0)
        }
    }

    // MARK: - Shared row chrome

    private var rowDivider: some View {
        Divider().opacity(0.5).padding(.leading, 68)
    }

    /// Grouped list row: a soft-tinted icon tile, title + subtitle, trailing
    /// accessory. The single row anatomy used by Management and Reports.
    private func navRow(icon: String, title: String, subtitle: String, accessory: String = "chevron.right") -> some View {
        HStack(spacing: 14) {
            ShiftIconTile(systemImage: icon, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: accessory)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
    }

    // MARK: - Go Live

    private func startLiveMode(for event: EventModel) {
        let allBlocks = (event.tracks ?? [])
            .flatMap { $0.blocks ?? [] }
            .sorted(by: { $0.scheduledStart < $1.scheduledStart })

        event.applyGoLiveMutation()
        AnalyticsService.send(.eventGoLive)
        let activeBlock = allBlocks.first(where: { $0.status == .active })

        // Persist + enqueue through the Outbox so the go-live status (and the
        // activated first block) syncs to shared vendors — a bare
        // `modelContext.save()` would never leave this device.
        Task { @MainActor in
            try? await eventRepo.save()
            watchSessionManager.sendCurrentContext()
        }

        // Schedule the local golden-hour/sunset reminder from the cached sun
        // times. Local-only, all tiers; no-ops if the times are unknown
        // or already within the 30-min lead window. The Task inherits this view's
        // MainActor context, so reading `event` stays isolation-safe.
        Task { await GoldenHourNotifier.schedule(for: event) }

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
}

// MARK: - EventStatus helpers used by EventRowView are reused here via the extension in EventRowView.swift
