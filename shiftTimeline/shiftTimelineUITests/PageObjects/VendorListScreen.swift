import XCTest

/// Page object for `VendorManagerView`.
///
/// `rootElement` anchors on the static nav bar title "Vendors", which is
/// always present regardless of whether the vendor list is empty or populated.
@MainActor
final class VendorListScreen: BaseScreen {

    override var rootElement: XCUIElement {
        app.navigationBars["Vendors"]
    }

    // MARK: - Elements

    var addVendorButton: XCUIElement {
        app.buttons[AccessibilityID.Vendors.addVendorButton]
    }

    /// The scroll view that contains vendor rows (absent in empty state).
    var vendorList: XCUIElement {
        app.scrollViews[AccessibilityID.Vendors.vendorList]
    }

    var emptyStateLabel: XCUIElement {
        app.staticTexts["No Vendors"]
    }

    // MARK: - Queries

    /// Returns the static text element for a vendor row by name.
    /// Tap it to open the vendor edit sheet.
    func vendorCell(name: String) -> XCUIElement {
        app.staticTexts[name]
    }

    // MARK: - Actions

    /// Taps Add Vendor to open the vendor form sheet.
    /// Returns `self` — `VendorFormSheet` doesn't have its own page object yet.
    @discardableResult
    func tapAddVendor() -> Self {
        addVendorButton.tap()
        return self
    }
}
