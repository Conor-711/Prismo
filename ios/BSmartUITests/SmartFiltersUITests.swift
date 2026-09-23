import XCTest

final class SmartFiltersUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testDirectSelectionsCombinePersistAndReset() {
        let app = openFilters()
        let results = app.buttons["smart.filters.results"]
        let total = count(results)
        XCTAssertGreaterThan(total, 0)
        XCTAssertEqual(app.pickers.count, 0)
        let platform = app.buttons["smart.filter.platform.X"]
        platform.tap()
        XCTAssertTrue(platform.isSelected)
        let platformCount = count(results)
        XCTAssertLessThanOrEqual(platformCount, total)
        let rank = app.buttons["smart.filter.rank.Top 25%"]
        reveal(rank, app)
        rank.tap()
        XCTAssertTrue(rank.isSelected)
        XCTAssertLessThanOrEqual(count(results), platformCount)
        let horizon = app.buttons["smart.filter.horizon.Short term"]
        reveal(horizon, app)
        horizon.tap()
        XCTAssertTrue(horizon.isSelected)
        let filtered = count(results)
        XCTAssertTrue(results.isHittable)
        results.tap()
        XCTAssertFalse(results.exists)
        app.buttons["smart.account.filters"].tap()
        XCTAssertTrue(results.waitForExistence(timeout: 5))
        XCTAssertEqual(count(results), filtered)
        XCTAssertTrue(platform.isSelected)
        app.buttons["smart.filters.reset"].tap()
        XCTAssertEqual(count(results), total)
        XCTAssertTrue(app.buttons["smart.filter.platform.All platforms"].isSelected)
    }

    func testMoneyUsesDirectChoicesAndKeepsAccountFiltersSeparate() {
        let app = openFilters()
        app.buttons["smart.filter.platform.X"].tap()
        app.buttons["smart.filters.results"].tap()
        app.descendants(matching: .any)["smart.section.money"].tap()
        app.buttons["smart.money.filters"].tap()
        let results = app.buttons["smart.filters.results"]
        XCTAssertTrue(results.waitForExistence(timeout: 5))
        let total = count(results)
        let short = app.buttons["smart.filter.direction.Short"]
        reveal(short, app)
        short.tap()
        XCTAssertTrue(short.isSelected)
        XCTAssertLessThanOrEqual(count(results), total)
        app.buttons["smart.filters.reset"].tap()
        XCTAssertEqual(count(results), total)
        app.buttons["smart.filters.results"].tap()
        app.descendants(matching: .any)["smart.section.accounts"].tap()
        app.buttons["smart.account.filters"].tap()
        XCTAssertTrue(app.buttons["smart.filter.platform.X"].isSelected)
    }

    func testChineseLargeTextOptionsStayInsideSheet() {
        let app = openFilters(chinese: true)
        for id in ["smart.filter.platform.X", "smart.filter.rank.Top 25%", "smart.filter.horizon.Short term"] {
            let button = app.buttons[id]
            reveal(button, app)
            XCTAssertTrue(button.isHittable)
            XCTAssertGreaterThanOrEqual(button.frame.height, 43.5)
            XCTAssertGreaterThanOrEqual(button.frame.minX, app.frame.minX)
            XCTAssertLessThanOrEqual(button.frame.maxX, app.frame.maxX)
            button.tap()
            XCTAssertTrue(button.isSelected)
        }
        XCTAssertTrue(app.buttons["smart.filters.results"].isHittable)
        XCTAssertEqual(app.pickers.count, 0)
        app.buttons["smart.filters.reset"].tap()
        app.buttons["smart.filters.results"].tap()
        let row = app.buttons["smart.account.row.first"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.isHittable)
        XCTAssertGreaterThanOrEqual(row.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(row.frame.maxX, app.frame.maxX)
        let tab = app.buttons["smart.section.accounts"]
        XCTAssertGreaterThanOrEqual(tab.frame.height, 44)
        XCTAssertLessThanOrEqual(tab.frame.maxX, app.frame.maxX)
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["smart.account.detail"].waitForExistence(timeout: 5))
    }

    func testHubSwipesBetweenAccountsAndMoneyWithoutLosingFilters() {
        let app = openFilters()
        app.buttons["smart.filter.platform.X"].tap()
        app.buttons["smart.filters.results"].tap()
        let accounts = app.scrollViews["smart.page.accounts"]
        XCTAssertTrue(accounts.waitForExistence(timeout: 5))
        accounts.swipeLeft()
        let moneyFilter = app.buttons["smart.money.filters"]
        XCTAssertTrue(moneyFilter.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["smart.section.money"].isSelected)
        let money = app.scrollViews["smart.page.money"]
        XCTAssertTrue(money.waitForExistence(timeout: 5))
        money.swipeRight()
        let accountFilter = app.buttons["smart.account.filters"]
        XCTAssertTrue(accountFilter.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["smart.section.accounts"].isSelected)
        accountFilter.tap()
        XCTAssertTrue(app.buttons["smart.filter.platform.X"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["smart.filter.platform.X"].isSelected)
    }

    private func count(_ button: XCUIElement) -> Int {
        let value = Int(button.value as? String ?? "")
        XCTAssertNotNil(value)
        return value ?? -1
    }

    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable && element.frame.maxY < app.buttons["smart.filters.results"].frame.minY { return }
            app.scrollViews["smart.filters.options"].swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    private func openFilters(chinese: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reset-state", "--ui-scenario=loaded", "--ui-trading-fixture",
                               "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)",
                               "-AppleLocale", chinese ? "zh_CN" : "en_US"]
        if chinese {
            app.launchArguments += ["--ui-appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"]
        }
        app.launch()
        let entry = app.buttons["discovery.open-directory"]
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        entry.tap()
        let filter = app.buttons["smart.account.filters"]
        if !filter.waitForExistence(timeout: 5) { print(app.debugDescription) }
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        filter.tap()
        XCTAssertTrue(app.buttons["smart.filters.results"].waitForExistence(timeout: 5))
        return app
    }
}
