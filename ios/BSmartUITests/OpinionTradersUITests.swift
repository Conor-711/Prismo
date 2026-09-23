import XCTest

final class OpinionTradersUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testCountExpandsAndPagesPublicTraders() {
        let app = openOpinion(fixture: true)
        let count = app.staticTexts["opinion.traders.count"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        XCTAssertEqual(count.label, "3")
        XCTAssertEqual(app.staticTexts["opinion.traders.volume"].label, "$364.75")
        count.tap()
        let casey = app.staticTexts["Casey"]
        let morgan = app.staticTexts["Morgan"]
        XCTAssertTrue(casey.waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Some traders keep their profiles private."].exists)
        let more = app.buttons["Load more"]
        more.tap()
        XCTAssertTrue(morgan.waitForExistence(timeout: 4))
        XCTAssertLessThan(casey.frame.minY, morgan.frame.minY)
        XCTAssertFalse(more.exists)
    }

    func testNormalExperienceHidesDemoData() {
        let app = openOpinion(fixture: false)
        XCTAssertFalse(app.staticTexts["opinion.traders.demo.count"].exists)
        XCTAssertFalse(app.buttons["opinion.traders.demo.open"].exists)
    }

    private func openOpinion(fixture: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reset-state", "--ui-scenario=loaded", "--ui-trading-fixture", "--ui-search-fixture",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-bsmart.app-language", "en"]
        if fixture { app.launchArguments.append("--ui-opinion-traders-fixture") }
        app.launch()
        let search = app.buttons["app.tab.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        let input = app.textFields["search.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap(); input.typeText("NBIS")
        app.buttons["search.filter.opinions"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "search.result.opinion:")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.tap()
        if fixture {
            let entry = app.staticTexts["opinion.traders.count"]
            XCTAssertTrue(entry.waitForExistence(timeout: 5))
        }
        return app
    }

}
