import XCTest

/// Page object for `TemplateBrowserView`.
///
/// `rootElement` anchors on the nav bar title "Templates". The large title
/// display mode means the nav bar element carries the "Templates" identifier
/// reliably after scroll-down as well.
@MainActor
final class TemplatePickerScreen: BaseScreen {

    override var rootElement: XCUIElement {
        app.navigationBars["Templates"]
    }

    // MARK: - Elements

    /// The scroll view that wraps the template grid (absent during loading and error states).
    var templateList: XCUIElement {
        app.scrollViews[AccessibilityID.Templates.templateList]
    }

    var emptyStateLabel: XCUIElement {
        app.staticTexts["No Templates"]
    }

    // MARK: - Queries

    /// Returns the static text element for a template card by template name.
    func templateCard(name: String) -> XCUIElement {
        app.staticTexts[name]
    }

    // MARK: - Actions

    /// Taps a template card by name to navigate to the template preview.
    /// Returns `self` — `TemplatePreviewView` doesn't have its own page object yet.
    @discardableResult
    func tapTemplate(name: String) -> Self {
        templateCard(name: name).tap()
        return self
    }
}
