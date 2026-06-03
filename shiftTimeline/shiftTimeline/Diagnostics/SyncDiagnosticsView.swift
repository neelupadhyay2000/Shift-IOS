import SwiftUI
import SwiftData
import UIKit
import Models
import Services

/// On-device diagnostics for the CloudKit share/sync funnel.
///
/// Cable-free: surfaces live status, per-event share state, a chronological
/// event log, and manual triggers — plus a Copy/Share button so the full log
/// can be pasted back for analysis without plugging the device into a Mac.
struct SyncDiagnosticsView: View {

    @Query(sort: \EventModel.date) private var events: [EventModel]

    @State private var isRunningAction = false
    @State private var lastActionResult: String?

    private let diagnostics = SyncDiagnosticsCenter.shared

    var body: some View {
        // Periodic re-render keeps the live status + log fresh without Combine.
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            List {
                liveStatusSection
                actionsSection
                eventsSection
                logSection
            }
        }
        .navigationTitle("Sync Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: diagnostics.exportText()) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }

    // MARK: - Live status

    private var liveStatusSection: some View {
        Section("Live Status") {
            statusRow("CloudKit Mirror", mirrorStateText, severity: mirrorSeverity)
            statusRow("iCloud Account", latestParam(category: .account, key: "value") ?? "unknown")
            statusRow("User Identity", CloudKitIdentity.shared.currentUserRecordName != nil ? "present" : "missing",
                      severity: CloudKitIdentity.shared.currentUserRecordName != nil ? .info : .warning)
            statusRow("Subscription", SharedZoneSubscriptionManager.shared.isSubscribed ? "registered" : "not registered",
                      severity: SharedZoneSubscriptionManager.shared.isSubscribed ? .info : .warning)
            statusRow("Last Silent Push", relativeTimeOf(category: .push, name: "silentPushReceived") ?? "never",
                      severity: relativeTimeOf(category: .push, name: "silentPushReceived") == nil ? .warning : .info)
            statusRow("Last Poll Tick", relativeTimeOf(category: .push, name: "pollTick") ?? "never")
        }
    }

    // MARK: - Manual triggers

    private var actionsSection: some View {
        Section("Actions") {
            if let lastActionResult {
                Text(lastActionResult)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            actionButton("Force Sync Now") {
                await SharedZoneSubscriptionManager.shared.fetchChanges()
            }
            actionButton("Force Full Resync (clear tokens)") {
                SharedZoneSubscriptionManager.shared.resetAllChangeTokens()
                await SharedZoneSubscriptionManager.shared.fetchChanges()
            }
            actionButton("Re-register Subscription") {
                await SharedZoneSubscriptionManager.shared.forceReRegister()
            }
            actionButton("Check iCloud Account") {
                await CloudKitDiagnostics.checkAccountStatus()
            }
            actionButton("Inventory Shared Zones (vendor)") {
                await CloudKitDiagnostics.inventorySharedZones()
            }
            Button(role: .destructive) {
                diagnostics.clear()
            } label: {
                Text("Clear Log")
            }
        }
    }

    // MARK: - Per-event share status

    private var eventsSection: some View {
        Section("Events (\(events.count))") {
            if events.isEmpty {
                Text("No events on this device.")
                    .foregroundStyle(.secondary)
            }
            ForEach(events) { event in
                eventRow(event)
            }
        }
    }

    @ViewBuilder
    private func eventRow(_ event: EventModel) -> some View {
        let identity = CloudKitIdentity.shared.currentUserRecordName
        let isOwner = event.isOwnedBy(identity)
        VStack(alignment: .leading, spacing: 4) {
            Text(event.title.isEmpty ? "(untitled)" : event.title)
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                tag(isOwner ? "owner" : "shared", color: isOwner ? .blue : .purple)
                tag(event.shareURL != nil ? "hasShare" : "noShare",
                    color: event.shareURL != nil ? .green : .secondary)
                tag(event.ownerRecordName != nil ? "ownerSet" : "ownerNil",
                    color: event.ownerRecordName != nil ? .green : .orange)
                tag("\(event.vendors?.count ?? 0) vendors", color: .secondary)
            }
            .font(.caption2)
            HStack {
                let eventID = event.id
                Button("Inspect Share") {
                    runAction("Inspecting share for \(event.title)…") {
                        await CloudKitDiagnostics.inspectShare(eventID: eventID)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                if isOwner, event.shareURL != nil {
                    Button("Re-run Parent Repair") {
                        runRepair(for: event)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Event log

    private var logSection: some View {
        Section("Event Log (\(diagnostics.events.count))") {
            if diagnostics.events.isEmpty {
                Text("No diagnostic events recorded yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(diagnostics.events) { event in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("\(event.category.rawValue).\(event.name)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(color(for: event.severity))
                        Spacer()
                        Text(event.timestamp, format: .dateTime.hour().minute().second())
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if !event.params.isEmpty {
                        Text(paramsText(event.params))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func statusRow(_ label: String, _ value: String, severity: DiagnosticEvent.Severity = .info) -> some View {
        LabeledContent(label) {
            Text(value)
                .foregroundStyle(color(for: severity))
        }
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private func actionButton(_ title: String, _ action: @escaping @Sendable () async -> Void) -> some View {
        Button(title) {
            runAction("\(title)…", action)
        }
        .disabled(isRunningAction)
    }

    /// Runs a capture-free async action with running/done UI feedback.
    /// The closure is `@Sendable` so it can be wrapped in a `Task` under strict
    /// concurrency — per-event actions that need a non-Sendable model use
    /// dedicated methods (`runRepair`) instead.
    private func runAction(_ runningMessage: String, _ action: @escaping @Sendable () async -> Void) {
        guard !isRunningAction else { return }
        isRunningAction = true
        lastActionResult = runningMessage
        Task {
            await action()
            isRunningAction = false
            lastActionResult = "Done. See log below."
        }
    }

    /// Re-runs parent-field repair for an owned, shared event. Mirrors the
    /// inline `Task { await … }` pattern used at the production call sites
    /// (e.g. `LiveDashboardView`) so the non-Sendable `EventModel` stays within
    /// the MainActor-inherited Task context.
    private func runRepair(for event: EventModel) {
        guard !isRunningAction else { return }
        isRunningAction = true
        lastActionResult = "Repairing parent fields for \(event.title)…"
        Task {
            await CloudKitShareRepairService.repairParentFieldsIfShared(for: event)
            isRunningAction = false
            lastActionResult = "Done. See log below."
        }
    }

    private func color(for severity: DiagnosticEvent.Severity) -> Color {
        switch severity {
        case .info: return .primary
        case .warning: return .orange
        case .error: return .red
        }
    }

    private var mirrorStateText: String {
        switch PersistenceController.shared.cloudKitMirrorState {
        case .healthy: return "healthy"
        case .degraded: return "degraded"
        case .disabled: return "disabled"
        }
    }

    private var mirrorSeverity: DiagnosticEvent.Severity {
        switch PersistenceController.shared.cloudKitMirrorState {
        case .healthy: return .info
        case .degraded: return .warning
        case .disabled: return .error
        }
    }

    /// Most recent value of a param key for a given category, from the log.
    private func latestParam(category: DiagnosticEvent.Category, key: String) -> String? {
        diagnostics.events.first { $0.category == category && $0.params[key] != nil }?.params[key]
    }

    /// Relative description ("12s ago") of the most recent event matching name.
    private func relativeTimeOf(category: DiagnosticEvent.Category, name: String) -> String? {
        guard let event = diagnostics.events.first(where: { $0.category == category && $0.name == name }) else {
            return nil
        }
        return event.timestamp.formatted(.relative(presentation: .numeric))
    }

    private func paramsText(_ params: [String: String]) -> String {
        params.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "  ")
    }
}
