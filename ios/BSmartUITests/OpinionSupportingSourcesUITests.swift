import XCTest

final class OpinionSupportingSourcesUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch(chinese: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reset-state", "--ui-scenario=loaded", "--ui-trading-fixture",
                               "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)",
                               "-AppleLocale", chinese ? "zh_CN" : "en_US",
                               "-bsmart.app-language", chinese ? "zh-Hans" : "en"]
        app.launch()
        let smart = app.descendants(matching: .any)["app.tab.smart"]
        XCTAssertTrue(smart.waitForExistence(timeout: 10))
        smart.tap()
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, attempts: Int = 12) {
        for _ in 0..<attempts {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, element.identifier)
    }

    func testSourceOpensFromRealRepresentativeOpinionAndReturnsWithoutTabs() {
        let app = launch()
        let search = app.textFields["Investor or specialty"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Mark Hogan")
        let account = app.descendants(matching: .any)["smart.account.row.first"]
        XCTAssertTrue(account.waitForExistence(timeout: 5))
        account.tap()
        let sections = app.segmentedControls["smart.account.detail.section"]
        XCTAssertTrue(sections.waitForExistence(timeout: 5))
        sections.buttons["Track record"].tap()
        let ticker = app.buttons["account.work.select.NBIS"]
        reveal(ticker, in: app)
        ticker.tap()
        let evidence = app.buttons["account.work.evidence"]
        reveal(evidence, in: app)
        evidence.tap()
        let source = app.buttons["opinion.source.open.nebius-microsoft-20250908-6k"]
        reveal(source, in: app, attempts: 40)
        XCTAssertFalse(app.staticTexts["暂无可关联的官方披露"].exists)
        source.tap()
        XCTAssertTrue(app.descendants(matching: .any)["opinion.source.detail"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Nebius Group · SEC EDGAR"].exists)
        XCTAssertTrue(app.staticTexts["Regulatory filing"].exists)
        XCTAssertFalse(app.buttons["app.tab.smart"].isHittable)
        XCTAssertFalse(app.buttons["Track NVIDIA official"].exists)
        let original = app.descendants(matching: .any)["opinion.source.original"].firstMatch
        reveal(original, in: app)
        XCTAssertTrue(original.isHittable)
        app.buttons["detail.back"].tap()
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertTrue(source.isHittable)
        XCTAssertFalse(app.buttons["app.tab.smart"].isHittable)
    }

    func testOpinionWithoutSourcesHasNoModuleOrEmptyState() {
        let app = launch()
        let account = app.descendants(matching: .any)["smart.account.row.first"]
        XCTAssertTrue(account.waitForExistence(timeout: 5))
        account.tap()
        let evidence = app.descendants(matching: .any)["smart.account.latest-view.first"]
        reveal(evidence, in: app)
        evidence.tap()
        XCTAssertTrue(app.descendants(matching: .any)["smart.account.evidence.detail"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["opinion.sources"].exists)
        XCTAssertFalse(app.staticTexts["Supporting sources"].exists)
        XCTAssertFalse(app.staticTexts["暂无可关联的官方披露"].exists)
    }

    func testReaderKeepsOriginalAccessibleAndSupportsTextSize() {
        let app = launch()
        let account = app.descendants(matching: .any)["smart.account.row.first"]
        XCTAssertTrue(account.waitForExistence(timeout: 5))
        account.tap()
        let evidence = app.descendants(matching: .any)["smart.account.latest-view.first"]
        reveal(evidence, in: app)
        evidence.tap()
        let original = app.buttons["opinion.reader.show-original"]
        reveal(original, in: app)
        original.tap()
        XCTAssertTrue(app.descendants(matching: .any)["opinion.reader.original"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["opinion.reader.translation"].exists)
        XCTAssertTrue(app.buttons["opinion.reader.copy"].isHittable)
        let font = app.buttons["opinion.reader.text-size"]
        font.tap()
        let large = app.buttons["Large"].firstMatch
        XCTAssertTrue(large.waitForExistence(timeout: 3))
        large.tap()
        XCTAssertEqual(font.value as? String, "Large")
        XCTAssertTrue(original.isHittable)
        XCTAssertFalse(app.buttons["app.tab.smart"].isHittable)
    }

    func testChineseReaderSwitchesFullTranslationAndOriginal() {
        let app = launch(chinese: true)
        let search = app.textFields["投资者或专长"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Labeltrader")
        let account = app.descendants(matching: .any)["smart.account.row.first"]
        XCTAssertTrue(account.waitForExistence(timeout: 5))
        account.tap()
        let evidence = app.descendants(matching: .any)["smart.account.latest-view.first"]
        reveal(evidence, in: app)
        evidence.tap()
        let translation = app.buttons["opinion.reader.show-translation"]
        reveal(translation, in: app)
        XCTAssertTrue(app.descendants(matching: .any)["opinion.reader.translation"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["opinion.reader.original"].exists)
        let original = app.buttons["opinion.reader.show-original"]
        original.tap()
        XCTAssertTrue(app.descendants(matching: .any)["opinion.reader.original"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["opinion.reader.translation"].exists)
        translation.tap()
        XCTAssertTrue(app.descendants(matching: .any)["opinion.reader.translation"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["opinion.reader.original"].exists)
    }
}
