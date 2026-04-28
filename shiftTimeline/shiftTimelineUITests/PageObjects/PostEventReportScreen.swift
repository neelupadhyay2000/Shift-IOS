import XCTest

/// Page object for `PostEventReportPreviewView`.
///
/// `rootElement` anchors on the inline nav bar title "Post-Event Report".
/// The export button only appears after PDF generation completes, so tests
/// that interact with it should use `waitForExistence` with a generous timeout.
@MainActor
final class PostEventReportScreen: BaseScreen {

    override var rootElement: XCUIElement {
        app.navigationBars["Post-Event Report"]
    }

    // MARK: - Elements

    /// The Share Report toolbar button. Only present after PDF generation succeeds.
    var exportButton: XCUIElement {
        app.buttons[AccessibilityID.Report.exportButton]
    }

    /// Loading indicator shown while the PDF is being generated.
    var generatingIndicator: XCUIElement {
        app.staticTexts["Generating Report\u{2026}"]
    }

    // MARK: - Actions

    /// Waits for the export button to become available (PDF generation can take
    /// a few seconds) then taps it to open the system share sheet.
    @discardableResult
    func tapExport(timeout: TimeInterval = 10) -> Self {
        XCTAssertTrue(
            exportButton.waitForExistence(timeout: timeout),
            "PostEventReportScreen — exportButton did not appear within \(timeout)s"
        )
        exportButton.tap()
        return self
    }
}
