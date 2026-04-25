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
    }

    private func generateReport() async {
        guard let event else {
            isGenerating = false
            return
        }
        #if os(iOS)
        // Ensure a report exists. This is a no-op when one is already cached.
        let report = event.postEventReport ?? PostEventReportGenerator.generate(for: event)
        let generator = PostEventReportPDFGenerator()
        let fileName = generator.fileName(for: event)
        let data = generator.generate(report: report, event: event)

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        let writtenURL: URL? = {
            do {
                try data.write(to: tempURL, options: .atomic)
                return tempURL
            } catch {
                return nil
            }
        }()

        pdfData = data
        pdfFileURL = writtenURL
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
        if pdfView.document?.dataRepresentation() != data {
            pdfView.document = PDFDocument(data: data)
        }
    }
}
