import Models
import Services
import SwiftData
import SwiftUI
import WidgetKit

/// Displays the details for a single event.
///
/// Fetched by `id` so the view works correctly whether pushed on iPhone
/// or shown in the iPad detail column.
struct EventDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(WatchSessionManager.self) private var watchSessionManager
    @Environment(LiveActivityManager.self) private var liveActivityManager
    @Environment(SupabaseAuthService.self) private var authService
    @Environment(\.scenePhase) private var scenePhase

    @Query private var results: [EventModel]

    @State private var paywallTrigger: PaywallTrigger?
    @State private var isShowingEditSheet = false
    @State private var isShowingVendorSharing = false
    @State private var isShowingSignIn = false
    /// Set when sign-in was prompted by a share attempt, so the share flow
    /// resumes automatically once the sign-in sheet dismisses.
    @State private var pendingShareAfterSignIn = false
    /// Drives the per-event Supabase Realtime channel while signed in and viewing
    /// an event — a vendor's shared timeline (SHIFT-631) or the planner watching
    /// vendor acknowledgments land in the ack grid (SHIFT-633). Lazily created.
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
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $paywallTrigger) { trigger in
            PaywallView(trigger: trigger)
        }
        .sheet(isPresented: $isShowingEditSheet) {
            if let event {
                EditEventSheet(event: event)
            }
        }
        .sheet(isPresented: $isShowingSignIn, onDismiss: resumeShareAfterSignIn) {
            SignInView()
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

    // MARK: - Realtime (SHIFT-631)

    /// Subscribes to the event's Supabase Realtime channel while signed in and
    /// viewing the event, so remote changes appear live without a manual refresh
    /// (the `RealtimeChangeApplier` writes into the shared `modelContext`, which
    /// `@Query` reflects). Serves both a vendor watching a shared timeline
    /// (SHIFT-631) and the planner watching vendor acknowledgments land in the ack
    /// grid (SHIFT-633). Signed-out / local-only use is not streamed.
    ///
    /// NOTE: when the data-layer cutover wires the planner's write path to
    /// Supabase, a shared `RealtimeEchoSuppressor` must be passed to both the write
    /// path and this applier so the planner's own writes aren't re-applied as echoes.
    private func configureRealtime() {
        guard authService.currentProfileID != nil else {
            realtime?.setActiveEvent(nil)
            return
        }
        if realtime == nil {
            let client = SupabaseClientProvider.shared.client
            realtime = RealtimeLifecycleManager(
                service: RealtimeSyncService(client: client),
                applier: RealtimeChangeApplier(context: modelContext),
                isForeground: scenePhase == .active
            )
        }
        realtime?.setActiveEvent(eventID)
    }

    private func eventContent(_ event: EventModel) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                let atRisk = atRiskOutdoorBlocks(for: event)
                ForEach(Array(atRisk.enumerated()), id: \.offset) { _, item in
                    RainWarningBanner(blockTitle: item.blockTitle, rainProbability: item.probability)
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
        .toolbar {
            if isOwner {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Edit")) {
                        isShowingEditSheet = true
                    }
                    .accessibilityLabel(String(localized: "Edit event details"))
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
                if FeatureFlags.vendorSharing {
                    if authService.isAuthenticated {
                        shareWithVendorsButton(event)
                    } else {
                        signInToShareButton
                    }
                }
            }
        }
    }

    /// Shown when sharing is enabled but the user is not signed in.
    private var signInToShareButton: some View {
        Button {
            pendingShareAfterSignIn = true
            isShowingSignIn = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Share with Vendors"))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(String(localized: "Sign in to invite vendors"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "lock.fill")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .premiumCard()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Share with Vendors — sign in required"))
    }

    private func shareWithVendorsButton(_: EventModel) -> some View {
        Button {
            presentVendorSharing()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text(String(localized: "Share with Vendors"))
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
    }

    private func startLiveMode(for event: EventModel) {
        let allBlocks = (event.tracks ?? [])
            .flatMap { $0.blocks ?? [] }
            .sorted(by: { $0.scheduledStart < $1.scheduledStart })

        event.applyGoLiveMutation()
        AnalyticsService.send(.eventGoLive)
        let activeBlock = allBlocks.first(where: { $0.status == .active })

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
