import XCTest

final class TodayInvestorActivityUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testInvestorCardsTimelineTrackingAndBothEvidenceRoutes() {
        let app = launch()
        let title = app.buttons["today.smart-updates.title"]
        reveal(title, in: app)
        XCTAssertFalse(app.buttons["today.standalone.title"].exists)
        title.tap()
        XCTAssertTrue(app.descendants(matching: .any)["smart-updates.collection"].waitForExistence(timeout: 5))
        let filter = app.segmentedControls["smart-updates.source-filter"]
        filter.buttons["Smart Account"].tap()
        let card = investorCard(in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let entries = card.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "smart-updates.evidence."))
        XCTAssertGreaterThan(entries.count, 0)
        XCTAssertLessThanOrEqual(entries.count, 2)
        let track = card.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "smart-updates.track.")).firstMatch
        let originalValue = track.value as? String
        track.tap()
        XCTAssertNotEqual(track.value as? String, originalValue)
        screenshot(app, "Smart updates - investor cards - Chinese dark")

        entries.firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["smart.account.evidence.detail"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()

        let timeline = card.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "smart-updates.open.")).firstMatch
        timeline.tap()
        XCTAssertTrue(app.descendants(matching: .any)["smart-updates.timeline"].waitForExistence(timeout: 5))
        XCTAssertTrue(evidence("account", in: app).exists)
        screenshot(app, "Smart updates - investor timeline")
        app.navigationBars.buttons.firstMatch.tap()

        filter.buttons["Smart Money"].tap()
        XCTAssertTrue(evidence("money", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(evidence("account", in: app).exists)
        screenshot(app, "Smart updates - money accounts")
        evidence("money", in: app).tap()
        XCTAssertTrue(app.descendants(matching: .any)["smart-money.movement-detail"].waitForExistence(timeout: 5))
    }

    func testDiscoveryWithoutHoldingsAndSearchInLightMode() {
        let app = launch(scenario: "first-use", language: "en", appearance: "light")
        let title = app.buttons["today.smart-updates.title"]
        reveal(title, in: app)
        title.tap()
        let search = app.textFields["smart-updates.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(investorCard(in: app).exists)
        screenshot(app, "Smart updates - light English without holdings")
        search.tap()
        search.typeText("no-investor-12345")
        XCTAssertTrue(app.descendants(matching: .any)["smart-updates.empty"].waitForExistence(timeout: 3))
        app.buttons["Clear search"].tap()
        XCTAssertTrue(investorCard(in: app).waitForExistence(timeout: 3))
    }

    func testNoDataRetainsSectionAndEmptyState() {
        let app = launch(scenario: "no-signals")
        let title = app.buttons["today.smart-updates.title"]
        reveal(title, in: app)
        title.tap()
        XCTAssertTrue(app.descendants(matching: .any)["smart-updates.empty"].waitForExistence(timeout: 5))
        XCTAssertFalse(investorCard(in: app).exists)
    }

    private func investorCard(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "smart-updates.investor.")).firstMatch
    }

    private func evidence(_ source: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "smart-updates.evidence.\(source).")).firstMatch
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(app.descendants(matching: .any)["today.screen"].waitForExistence(timeout: 10))
        let tab = app.buttons["today.tab.investors"]
        for _ in 0..<8 {
            if tab.isHittable { break }
            app.swipeUp()
        }
        tab.tap()
        for _ in 0..<20 {
            if element.exists && element.isHittable { return }
            app.swipeUp(velocity: .slow)
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
        app.launchArguments = ["--ui-reset-state", "--ui-scenario=\(scenario)", "--ui-trading-fixture",
                               "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN",
                               "--ui-appearance", appearance]
        if scenario == "first-use" { app.launchArguments += ["-bsmart.portfolio-setup-complete.v1", "YES"] }
        app.launch()
        return app
    }
}
