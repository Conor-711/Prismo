import XCTest

final class RepresentativeWorksUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testAuthorUsesTwoSectionsAndSwitchesRepresentativeChartInPlace() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reset-state", "--ui-scenario=loaded", "--ui-trading-fixture",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let smart = app.descendants(matching: .any)["app.tab.smart"]
        XCTAssertTrue(smart.waitForExistence(timeout: 8))
        smart.tap()
        let account = app.descendants(matching: .any)["smart.account.row.first"]
        XCTAssertTrue(account.waitForExistence(timeout: 5))
        account.tap()
        let picker = app.segmentedControls["smart.account.detail.section"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertEqual(picker.buttons.count, 2)
        XCTAssertFalse(picker.buttons["Views"].exists)
        picker.buttons["Track record"].tap()
        let selectors = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "account.work.select."))
        for _ in 0..<8 {
            if selectors.firstMatch.isHittable { break }
            app.swipeUp()
        }
        XCTAssertEqual(selectors.count, 3)
        let first = selectors.element(boundBy: 0)
        let second = selectors.element(boundBy: 1)
        XCTAssertTrue(first.isSelected)
        second.tap()
        XCTAssertTrue(second.isSelected)
        XCTAssertFalse(first.isSelected)
        let symbol = String(second.identifier.dropFirst("account.work.select.".count))
        for _ in 0..<3 {
            if app.buttons["account.work.marker.0"].isHittable { break }
            app.swipeUp()
        }
        XCTAssertEqual(app.staticTexts["account.work.ticker"].label, symbol)
        let chart = app.descendants(matching: .any).matching(identifier: "account.work.chart").firstMatch
        XCTAssertEqual(app.staticTexts.matching(identifier: "account.work.ticker").count, 1)
        XCTAssertTrue(chart.exists)
        let bubble = app.buttons["account.work.marker.1"]
        for _ in 0..<3 {
            if bubble.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(bubble.isHittable, app.debugDescription)
        bubble.tap()
        XCTAssertTrue(app.buttons["account.work.opinion.1"].isSelected)
        XCTAssertFalse(app.buttons["account.work.opinion.0"].isSelected)
        XCTAssertTrue(app.staticTexts["account.work.selected-thesis"].exists)
        let line = app.buttons["account.work.line"]
        if !line.isHittable { app.swipeDown() }
        line.tap()
        XCTAssertTrue(line.isSelected)
        XCTAssertTrue(app.buttons["account.work.marker.0"].exists)
        XCTAssertFalse(app.buttons["app.tab.smart"].isHittable)
    }
}
