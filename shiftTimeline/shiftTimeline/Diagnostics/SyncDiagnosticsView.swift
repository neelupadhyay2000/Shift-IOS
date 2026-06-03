import SwiftUI
import Models
import Services

/// On-device diagnostic log.
///
/// CloudKit health rows and action buttons have been removed (SHIFT-531).
/// Supabase sync diagnostics will be added in E12/E16.
struct SyncDiagnosticsView: View {

    private let diagnostics = SyncDiagnosticsCenter.shared

    var body: some View {
        // Periodic re-render keeps the live log fresh without Combine.
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            List {
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
