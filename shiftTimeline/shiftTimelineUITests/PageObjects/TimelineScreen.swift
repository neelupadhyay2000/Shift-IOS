import XCTest

/// Page object for `TimelineBuilderView`.
///
/// `rootElement` anchors on the Add Block toolbar button, which carries a fixed
/// accessibility identifier regardless of the dynamic event title in the nav bar.
/// For read-only events the button is absent — check `blockList` existence instead.
@MainActor
final class TimelineScreen: BaseScreen {

    override var rootElement: XCUIElement {
        app.buttons[AccessibilityID.Timeline.addBlockButton]
    }

    // MARK: - Elements

    var addBlockButton: XCUIElement {
        app.buttons[AccessibilityID.Timeline.addBlockButton]
    }

    var blockList: XCUIElement {
        app.scrollViews[AccessibilityID.Timeline.blockList]
    }

    var trackTabBar: XCUIElement {
        app.otherElements[AccessibilityID.Timeline.trackTabBar]
    }

    // MARK: - Queries

    func blockCell(title: String) -> XCUIElement {
        app.staticTexts[title]
    }

    // MARK: - Actions

    /// Tap an existing block card to open the Block Inspector sheet (iPhone).
    @discardableResult
    func tapBlock(title: String) -> BlockInspectorScreen {
        blockCell(title: title).tap()
        let screen = BlockInspectorScreen(app: app)
        screen.waitForExistence()
        return screen
    }

    /// Tap the Add Block toolbar button to open the create-block sheet.
    /// Returns `self` because the create sheet is a separate, untested flow here.
    @discardableResult
    func tapAddBlock() -> Self {
        addBlockButton.tap()
        return self
    }
}
