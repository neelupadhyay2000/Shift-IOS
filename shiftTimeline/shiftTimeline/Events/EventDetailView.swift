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
    /// The cutover's shared echo suppressor (SHIFT-658) — non-nil only when the
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
    /// The shared `RealtimeEchoSuppressor` (SHIFT-658) is injected from the
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
            VStack(alignment: .leading, spacing: 16) {
                let atRisk = atRiskOutdoorBlocks(for: event)
                ForEach(Array(atRisk.enumerated()), id: \.offset) { _, item in
                    RainWarningBanner(blockTitle: item.blockTitle, rainProbability: item.probability)
                }
                heroSection(event)
                primaryAction(event)
                statsRow(event)
                detailsCard(event)
                tracksCard(event)
                actionsCard(event)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background { ProBackground() }
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

    // MARK: - Hero (Luma-style: title on the canvas, typography does the work)

    private func heroSection(_ event: EventModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Status · countdown micro-line — the "when and what state" at a glance.
            HStack(spacing: 6) {
                Circle()
                    .fill(event.status.tintColor)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text(event.status.label)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .kerning(0.8)
                    .foregroundStyle(event.status.tintColor)
                Text(verbatim: "·")
                    .foregroundStyle(.quaternary)
                Text(EventCountdown.label(for: event.date))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(event.status.label), \(EventCountdown.label(for: event.date))")

            Text(event.title)
                .font(.largeTitle.weight(.bold))
                .lineLimit(3)
                .minimumScaleFactor(0.75)

            VStack(alignment: .leading, spacing: 6) {
                heroMetaRow(icon: "calendar", text: event.date.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                if !event.venueNames.isEmpty {
                    heroMetaRow(icon: "mappin.and.ellipse", text: event.venueNames.joined(separator: ", "))
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private func heroMetaRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.tertiary)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    // MARK: - Primary action (Go Live / View Live — the one loud element)

    @ViewBuilder
    private func primaryAction(_ event: EventModel) -> some View {
        if isOwner {
            NavigationLink(value: EventDestination.liveDashboard(eventID: event.id)) {
                liveCTALabel(String(localized: "Go Live"))
            }
            .simultaneousGesture(TapGesture().onEnded { startLiveMode(for: event) })
            .buttonStyle(.pressableCard)
            .accessibilityLabel(String(localized: "Go Live"))
            .accessibilityHint(String(localized: "Starts live event execution mode"))
        } else if event.status == .live {
            // Vendor on a shared event that's currently live → read-only live view.
            NavigationLink(value: EventDestination.liveDashboard(eventID: event.id)) {
                liveCTALabel(String(localized: "View Live"))
            }
            .buttonStyle(.pressableCard)
            .accessibilityLabel(String(localized: "View Live"))
            .accessibilityHint(String(localized: "Opens the live timeline"))
        }
    }

    private func liveCTALabel(_ title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 17, weight: .bold))
                .symbolEffect(.variableColor.iterative, options: .repeating)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
            Spacer()
            Image(systemName: "arrow.right")
                .font(.subheadline.weight(.bold))
                .opacity(0.9)
                .accessibilityHidden(true)
        }
        .foregroundStyle(.white)
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .background(ShiftPalette.live, in: RoundedRectangle(cornerRadius: ShiftDesign.cardRadius, style: .continuous))
        .shadow(color: ShiftPalette.live.opacity(0.35), radius: 12, y: 5)
    }

    // MARK: - Stat tiles (numbers are the heroes — Flighty data look)

    private func statsRow(_ event: EventModel) -> some View {
        let allBlocks = (event.tracks ?? []).flatMap { $0.blocks ?? [] }
        let blockCount = allBlocks.count
        // A vendor sees how many blocks are theirs up front (before opening
        // the timeline); the owner sees the total block count.
        let assignedToMe = allBlocks.filter { $0.isAssigned(to: authService.currentProfileID) }.count
        let vendorCount = (event.vendors ?? []).count

        return HStack(spacing: 12) {
            NavigationLink(value: EventDestination.timelineBuilder(eventID: event.id)) {
                statTile(
                    value: isOwner ? "\(blockCount)" : "\(assignedToMe)",
                    label: isOwner
                        ? String(localized: "timeline_card_label", defaultValue: "Timeline")
                        : String(localized: "assigned to you"),
                    icon: "calendar.day.timeline.leading"
                )
            }
            .buttonStyle(.pressableCard)
            .accessibilityLabel(
                isOwner
                    ? String(localized: "\(blockCount) timeline blocks")
                    : String(localized: "\(assignedToMe) blocks assigned to you")
            )
            .accessibilityHint(String(localized: "Opens timeline builder"))

            NavigationLink(value: EventDestination.vendorManager(eventID: event.id)) {
                statTile(value: "\(vendorCount)", label: String(localized: "Vendors"), icon: "person.2")
            }
            .buttonStyle(.pressableCard)
            .disabled(!isOwner)
            .opacity(isOwner ? 1 : 0.55)
            .accessibilityLabel(String(localized: "\(vendorCount) vendors assigned"))
            .accessibilityHint(isOwner ? String(localized: "Opens vendor manager") : String(localized: "Only available to event owner"))
        }
    }

    private func statTile(value: String, label: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(value)
                    .font(.system(size: 32, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Spacer()
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ShiftPalette.accent)
                    .accessibilityHidden(true)
            }
            Text(label)
                .microLabel()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .proCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label)")
    }

    // MARK: - Actions (grouped, monochrome — Luma style)

    @ViewBuilder
    private func actionsCard(_ event: EventModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Actions")).microLabel()

            VStack(spacing: 0) {
                NavigationLink(value: EventDestination.pdfExport(eventID: event.id)) {
                    actionRow(icon: "doc.richtext", title: String(localized: "Export PDF"))
                }
                .buttonStyle(.pressableCard)
                .accessibilityHint(String(localized: "Generates a PDF timeline document"))

                rowDivider
                Button { isShowingSaveAsTemplate = true } label: {
                    actionRow(icon: "rectangle.stack.badge.plus", title: String(localized: "Save as Template"))
                }
                .buttonStyle(.pressableCard)
                .accessibilityHint(String(localized: "Saves this timeline as a reusable template"))

                if event.status == .completed {
                    rowDivider
                    NavigationLink(value: EventDestination.postEventReport(eventID: event.id)) {
                        actionRow(icon: "chart.bar.doc.horizontal", title: String(localized: "Export Report"))
                    }
                    .buttonStyle(.pressableCard)
                    .accessibilityIdentifier(AccessibilityID.Report.exportButton)
                    .accessibilityLabel(String(localized: "Export Post-Event Report"))
                    .accessibilityHint(String(localized: "Generates a post-event summary report"))
                }

                if isOwner, FeatureFlags.supabaseSync {
                    rowDivider
                    if authService.isAuthenticated {
                        Button { presentVendorSharing() } label: {
                            actionRow(icon: "square.and.arrow.up", title: String(localized: "Share with Vendors"))
                        }
                        .buttonStyle(.pressableCard)
                    } else {
                        Button {
                            pendingShareAfterSignIn = true
                            isShowingSignIn = true
                        } label: {
                            actionRow(
                                icon: "square.and.arrow.up",
                                title: String(localized: "Share with Vendors"),
                                subtitle: String(localized: "Sign in to invite vendors"),
                                accessory: "lock.fill"
                            )
                        }
                        .buttonStyle(.pressableCard)
                        .accessibilityLabel(String(localized: "Share with Vendors — sign in required"))
                    }
                }
            }
            .proCard(padding: 0)
        }
    }

    private var rowDivider: some View {
        Divider().opacity(0.6).padding(.leading, 52)
    }

    private func actionRow(icon: String, title: String, subtitle: String? = nil, accessory: String = "chevron.right") -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(ShiftPalette.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: accessory)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }

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
        // times (SHIFT-649). Local-only, all tiers; no-ops if the times are unknown
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

    // MARK: - Details (location + sun times)

    @ViewBuilder
    private func detailsCard(_ event: EventModel) -> some View {
        if event.latitude != 0 || event.longitude != 0 {
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "Details")).microLabel()

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 24) {
                        locationItem(label: String(localized: "Lat"), value: String(format: "%.4f", event.latitude))
                        locationItem(label: String(localized: "Lon"), value: String(format: "%.4f", event.longitude))
                    }

                    if event.sunsetTime != nil || event.goldenHourStart != nil {
                        Divider().opacity(0.6)
                        if let sunset = event.sunsetTime {
                            sunRow(icon: "sunset.fill", label: String(localized: "Sunset"), time: sunset)
                        }
                        if let golden = event.goldenHourStart {
                            sunRow(icon: "sun.and.horizon.fill", label: String(localized: "Golden Hour"), time: golden)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .proCard()
            }
        }
    }

    /// Sun/time-of-day row — the only place the warm accent appears.
    private func sunRow(icon: String, label: String, time: Date) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(ShiftPalette.warm)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(time, format: .dateTime.hour().minute())
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(time.formatted(.dateTime.hour().minute()))")
    }

    // MARK: - Tracks

    private func tracksCard(_ event: EventModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Tracks")).microLabel()

            VStack(spacing: 0) {
                let tracks = (event.tracks ?? []).sorted(by: { $0.sortOrder < $1.sortOrder })
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    if index > 0 {
                        Divider().opacity(0.6).padding(.leading, 16)
                    }
                    trackRow(track)
                }
            }
            .proCard(padding: 0)
        }
    }

    private func trackRow(_ track: TimelineTrack) -> some View {
        HStack(spacing: 10) {
            Text(track.name)
                .font(.subheadline.weight(.medium))
            if track.isDefault {
                Text(String(localized: "Default"))
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .kerning(0.5)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(ShiftPalette.soft(ShiftPalette.accent), in: Capsule())
                    .foregroundStyle(ShiftPalette.accent)
            }
            Spacer()
            Text(String(localized: "\((track.blocks ?? []).count) blocks"))
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }

    private func locationItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).microLabel()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
    }
}

// MARK: - EventStatus helpers used by EventRowView are reused here via the extension in EventRowView.swift
