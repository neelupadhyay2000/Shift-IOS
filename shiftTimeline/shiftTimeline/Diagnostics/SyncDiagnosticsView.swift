import SwiftUI
import Models
import Services

/// On-device Supabase sync diagnostics.
///
/// Shows the sync funnel end-to-end — a status row per stage (auth → connect →
/// subscribe → fetch → applyRemote → push → conflict) plus the full, newest-first
/// event log. The log stays copy/shareable via the toolbar export.
struct SyncDiagnosticsView: View {

    private let diagnostics: SyncDiagnosticsCenter

    init(diagnostics: SyncDiagnosticsCenter = .shared) {
        self.diagnostics = diagnostics
    }

    /// The Supabase sync funnel, in pipeline order. `notify` is intentionally
    /// excluded — it isn't a sync stage; its events still appear in the log.
    private let funnelStages: [DiagnosticEvent.Category] = [
        .auth, .connect, .subscribe, .fetch, .applyRemote, .push, .conflict,
    ]

    var body: some View {
        // Periodic re-render keeps the live log fresh without Combine.
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            List {
                funnelSection
                logSection
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: diagnostics.exportText()) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }

    // MARK: - Funnel overview

    private var funnelSection: some View {
        Section("Supabase Funnel") {
            ForEach(funnelStages, id: \.self) { stage in
                funnelRow(for: stage)
            }
        }
    }

    private func funnelRow(for category: DiagnosticEvent.Category) -> some View {
        let categoryEvents = diagnostics.events.filter { $0.category == category }
        let latest = categoryEvents.first // events are newest-first
        let symbol = latest.map { statusSymbol(for: $0.severity) } ?? "circle"
        let tint = latest.map { color(for: $0.severity) } ?? Color.secondary

        return HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(tint)
            Text(displayName(for: category))
                .font(.subheadline)
            Spacer()
            if let latest {
                Text(latest.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("\(categoryEvents.count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 20, alignment: .trailing)
        }
    }

    // MARK: - Event log

    private var logSection: some View {
        Section("Event Log (\(diagnostics.events.count))") {
            Button(role: .destructive) {
                diagnostics.clear()
            } label: {
                Text("Clear Log")
            }
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

    private func displayName(for category: DiagnosticEvent.Category) -> String {
        switch category {
        case .auth: return "Auth"
        case .connect: return "Connect"
        case .subscribe: return "Subscribe"
        case .fetch: return "Fetch"
        case .applyRemote: return "Apply Remote"
        case .push: return "Push"
        case .conflict: return "Conflict"
        case .notify: return "Notify"
        }
    }

    private func statusSymbol(for severity: DiagnosticEvent.Severity) -> String {
        switch severity {
        case .info: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private func color(for severity: DiagnosticEvent.Severity) -> Color {
        switch severity {
        case .info: return .primary
        case .warning: return .orange
        case .error: return .red
        }
    }

    private func paramsText(_ params: [String: String]) -> String {
        params.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "  ")
    }
}

#Preview {
    let center = SyncDiagnosticsCenter(
        defaults: .standard,
        storageKey: "preview.shift.syncDiagnostics",
        maxEvents: 100
    )
    center.clear()
    center.record(.auth, "signedIn", params: ["provider": "apple"])
    center.record(.connect, "connected")
    center.record(.subscribe, "subscribed", params: ["event": "summer-wedding"])
    center.record(.fetch, "hydrated", params: ["events": "3", "blocks": "42"])
    center.record(.applyRemote, "realtimeApplyFailed", params: ["table": "blocks"], severity: .error)
    center.record(.push, "remoteWriteFailed", params: ["table": "events"], severity: .error)

    return NavigationStack {
        SyncDiagnosticsView(diagnostics: center)
    }
}
