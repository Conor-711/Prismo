import XCTest

final class OpinionTradersUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testCountExpandsAndPagesPublicTraders() {
        let app = openOpinion(fixture: true)
        let count = app.staticTexts["opinion.traders.count"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        XCTAssertEqual(count.label, "3 people traded through this opinion")
        app.buttons["opinion.traders.expand"].tap()
        let casey = app.descendants(matching: .any)["opinion.trader.00000000-0000-4000-8000-000000000001"].firstMatch
        let morgan = app.descendants(matching: .any)["opinion.trader.00000000-0000-4000-8000-000000000002"].firstMatch
        XCTAssertTrue(casey.waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Some traders keep their profiles private."].exists)
        let more = app.buttons["opinion.traders.more"]
        reveal(more, app: app)
        more.tap()
        XCTAssertTrue(morgan.waitForExistence(timeout: 4))
        XCTAssertLessThan(casey.frame.minY, morgan.frame.minY)
        XCTAssertFalse(more.exists)
    }

    func testUnavailableShowsLabeledDemoWithPositionDetails() {
        let app = openOpinion(fixture: false)
        XCTAssertTrue(app.descendants(matching: .any)["opinion.traders.demo.badge"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["opinion.traders.count"].exists)
        XCTAssertEqual(app.staticTexts["opinion.traders.demo.count"].label, "8 people traded through this opinion")
        app.buttons["opinion.traders.expand"].tap()
        let first = app.descendants(matching: .any)["opinion.traders.demo.row.0"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 4))
        XCTAssertTrue(first.staticTexts["Casey"].exists)
        XCTAssertTrue(first.staticTexts["Entry price"].exists)
        XCTAssertTrue(first.staticTexts["Position value"].exists)
        XCTAssertTrue(first.staticTexts["3x Long"].exists)
        let more = app.buttons["opinion.traders.demo.more"]
        reveal(more, app: app)
        more.tap()
        XCTAssertTrue(app.descendants(matching: .any)["opinion.traders.demo.row.5"].firstMatch.exists)
        XCTAssertFalse(more.exists)
        XCTAssertFalse(app.staticTexts["opinion.traders.count"].exists)
    }

    private func openOpinion(fixture: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reset-state", "--ui-scenario=loaded", "--ui-trading-fixture",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-bsmart.app-language", "en"]
        if fixture { app.launchArguments.append("--ui-opinion-traders-fixture") }
        app.launch()
        let smart = app.buttons["app.tab.smart"]
        XCTAssertTrue(smart.waitForExistence(timeout: 10))
        smart.tap()
        let account = app.descendants(matching: .any)["smart.account.row.first"]
        XCTAssertTrue(account.waitForExistence(timeout: 5))
        account.tap()
        let evidence = app.descendants(matching: .any)["smart.account.latest-view.first"]
        reveal(evidence, app: app)
        evidence.tap()
        XCTAssertTrue(app.buttons["opinion.traders.expand"].waitForExistence(timeout: 5))
        return app
    }

    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<10 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }
}
