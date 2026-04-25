import SwiftUI
import PDFKit
import SwiftData
import UniformTypeIdentifiers
import Models
import Services

/// Full-screen PDF preview of the post-event report.
///
/// Mirrors the timeline `PDFExportPreviewView` — generates the PDF off the
/// main thread, stages it as a temporary file, and exposes a `ShareLink`
/// in the toolbar so the user can send the report to Files, Mail, AirDrop,
/// or any other share target.
///
/// The view loads the stored `PostEventReport` from `EventModel.postEventReport`.
/// If no report has been generated (e.g. the user navigated here before
/// completion finished), the view falls back to building a fresh one via
/// `PostEventReportGenerator.generate(for:)` so the share flow never dead-ends.
struct PostEventReportPreviewView: View {

    let eventID: UUID

    @Query private var results: [EventModel]
    @State private var pdfData: Data?
    @State private var pdfFileURL: URL?
    @State private var isGenerating = true
    @State private var shareError: String?

    private var event: EventModel? { results.first }

    init(eventID: UUID) {
        self.eventID = eventID
        _results = Query(
            filter: #Predicate<EventModel> { $0.id == eventID }
        )
    }

    var body: some View {
        Group {
            if isGenerating {
                ProgressView(String(localized: "Generating Report…"))
            } else if let pdfData {
                PDFKitView(data: pdfData)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                ContentUnavailableView(
                    String(localized: "Unable to Generate Report"),
                    systemImage: "exclamationmark.triangle"
                )
            }
        }
        .navigationTitle(String(localized: "Post-Event Report"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let pdfFileURL {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(
                        item: pdfFileURL,
                        preview: SharePreview(
                            event?.title ?? "Post-Event Report",
                            image: Image(systemName: "doc.richtext")
                        )
                    )
                    .accessibilityLabel(String(localized: "Share Report"))
                }
            }
        }
        .task {
            await generateReport()
        }
        .alert(
            String(localized: "Unable to Save Report"),
            isPresented: Binding(
                get: { shareError != nil },
                set: { if !$0 { shareError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(shareError ?? "")
        }
    }

    private func generateReport() async {
        guard let event else {
            isGenerating = false
            return
        }
        #if os(iOS)
        // Ensure a report exists. This is a no-op when one is already cached.
        // All access to the live `@Model` happens here on `@MainActor` —
        // we extract a `Sendable` snapshot before hopping off the actor so
        // the (CPU-heavy) PDF render does not jank the UI.
        let report = event.postEventReport ?? PostEventReportGenerator.generate(for: event)
        let summary = PostEventReportPDFGenerator.EventSummary(
            title: event.title,
            date: event.date
        )

        let result = await Task.detached(priority: .userInitiated) {
            () -> (data: Data, url: URL?, writeError: String?) in
            let pdfGenerator = PostEventReportPDFGenerator()
            let data = pdfGenerator.generate(report: report, event: summary)
            let fileName = pdfGenerator.fileName(for: summary)
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(fileName)
            do {
                try data.write(to: tempURL, options: .atomic)
                return (data, tempURL, nil)
            } catch {
                return (data, nil, error.localizedDescription)
            }
        }.value

        pdfData = result.data
        pdfFileURL = result.url
        if let writeError = result.writeError {
            shareError = writeError
        }
        #endif
        isGenerating = false
    }
}

// MARK: - PDFKit UIViewRepresentable

private struct PDFKitView: UIViewRepresentable {

    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.document = PDFDocument(data: data)
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        // `data` is a `let` from a single parent `@State` write; an identity
        // check is sufficient. Avoid `dataRepresentation()` which serialises
        // the entire document on every SwiftUI update pass.
        guard pdfView.document == nil else { return }
        pdfView.document = PDFDocument(data: data)
    }
}
