import XCTest

final class TodayHoldingsUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testHomepageModuleAndBothEvidenceRoutes() {
        let app = launch()
        let title = app.buttons["today.holdings.title"]
        reveal(title, in: app)
        if title.frame.minY > app.frame.height * 0.5 { app.swipeUp() }
        screenshot(app, "Holdings module - dark Chinese")
        title.tap()
        XCTAssertTrue(app.descendants(matching: .any)["holdings.collection"].waitForExistence(timeout: 5))
        screenshot(app, "Holdings collection - dark Chinese")
        let source = app.segmentedControls["holdings.source-filter"]
        source.buttons["Smart Account"].tap()
        let account = activity("account", in: app)
        XCTAssertTrue(account.waitForExistence(timeout: 5))
        account.tap()
        XCTAssertTrue(app.descendants(matching: .any)["smart.account.evidence.detail"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        source.buttons["Smart Money"].tap()
        let money = activity("money", in: app)
        XCTAssertTrue(money.waitForExistence(timeout: 5))
        XCTAssertFalse(activity("account", in: app).exists)
        screenshot(app, "Holdings Smart Money filter")
        money.tap()
        XCTAssertTrue(app.descendants(matching: .any)["smart-money.movement-detail"].waitForExistence(timeout: 5))
        screenshot(app, "Holdings Smart Money evidence")
    }

    func testEmptyPortfolioOffersAddAndUpdatesImmediately() {
        let app = launch(scenario: "first-use", language: "en")
        let add = app.buttons["holdings.add"]
        reveal(add, in: app)
        screenshot(app, "Holdings module - empty portfolio")
        add.tap()
        XCTAssertTrue(app.descendants(matching: .any)["position-editor.screen"].waitForExistence(timeout: 5))
        let symbol = app.textFields["position-editor.field.Ticker"]
        symbol.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        symbol.typeText("NVDA")
        let shares = app.textFields["position-editor.field.Shares"]
        shares.tap()
        shares.typeText("10")
        XCTAssertTrue(app.navigationBars.buttons["Add"].isEnabled)
        app.navigationBars.buttons["Add"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["position-editor.screen"].waitForNonExistence(timeout: 5))
        let title = app.buttons["today.holdings.title"]
        reveal(title, in: app)
        title.tap()
        XCTAssertTrue(app.buttons["holdings.ticker.NVDA"].waitForExistence(timeout: 5))
        XCTAssertTrue(activity("account", in: app).waitForExistence(timeout: 5))
    }

    func testLightModeTickerFilterAndWeightOnlyHolding() {
        let app = launch(scenario: "weight-only", language: "en", appearance: "light")
        let title = app.buttons["today.holdings.title"]
        reveal(title, in: app)
        title.tap()
        let ticker = app.buttons["holdings.ticker.NVDA"]
        XCTAssertTrue(ticker.waitForExistence(timeout: 5))
        ticker.tap()
        XCTAssertTrue(ticker.isSelected)
        XCTAssertTrue(app.staticTexts["Portfolio weight 35%"].firstMatch.exists)
        XCTAssertFalse(app.buttons["holdings.ticker.HOOD"].exists)
        screenshot(app, "Holdings collection - light English")
    }

    func testNoSignalsShowsHonestEmptyState() {
        let app = launch(scenario: "no-signals")
        let title = app.buttons["today.holdings.title"]
        reveal(title, in: app)
        title.tap()
        XCTAssertTrue(app.descendants(matching: .any)["holdings.empty"].waitForExistence(timeout: 5))
        XCTAssertFalse(activity("account", in: app).exists)
        XCTAssertFalse(activity("money", in: app).exists)
    }

    private func activity(_ source: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "holdings.activity.\(source).")).firstMatch
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(app.descendants(matching: .any)["today.screen"].waitForExistence(timeout: 10))
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launch(scenario: String = "loaded", language: String = "zh-Hans",
                        appearance: String = "dark") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reset-state", "--ui-scenario=\(scenario)",
                               "--ui-trading-fixture",
                               "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN",
                               "--ui-appearance", appearance]
        if scenario == "first-use" {
            // Returning user who has no holdings, not the first-launch onboarding flow.
            app.launchArguments += ["-bsmart.portfolio-setup-complete.v1", "YES"]
        }
        app.launch()
        return app
    }
}
