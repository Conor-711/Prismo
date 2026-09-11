import XCTest

final class PortfolioWorkspaceUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testWholePageScrollsAndTrendingLeadsTheCompleteDirectory() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reset-state", "--ui-scenario=loaded", "--ui-trading-fixture",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--ui-appearance", "light"]
        app.launch()
        let portfolio = app.buttons["app.tab.portfolio"]
        XCTAssertTrue(portfolio.waitForExistence(timeout: 8))
        portfolio.tap()
        let chart = app.descendants(matching: .any)["portfolio.value-chart"]
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
        let originalY = chart.frame.minY
        app.buttons["portfolio.period.1W"].tap()
        let page = app.scrollViews["portfolio.page.holdings"]
        let picker = app.descendants(matching: .any)["portfolio.section-picker"]
        let favoritesTab = app.buttons["portfolio.tab.watchlist"]
        let holdingsTab = app.buttons["portfolio.tab.holdings"]
        let allTab = app.buttons["portfolio.tab.allTickers"]
        XCTAssertLessThanOrEqual(favoritesTab.frame.minX - app.frame.minX, 20)
        XCTAssertEqual(holdingsTab.frame.minX - favoritesTab.frame.maxX, 24, accuracy: 2)
        XCTAssertEqual(allTab.frame.minX - holdingsTab.frame.maxX, 24, accuracy: 2)
        XCTAssertGreaterThan(app.frame.maxX - allTab.frame.maxX, 40)
        for _ in 0..<6 {
            if picker.frame.minY <= app.navigationBars.firstMatch.frame.maxY + 4 { break }
            page.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.75))
                .press(forDuration: 0.05, thenDragTo: page.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)),
                       withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        XCTAssertLessThan(chart.frame.minY, originalY - 80, "The summary must scroll away with the list")
        XCTAssertLessThanOrEqual(picker.frame.minY, app.navigationBars.firstMatch.frame.maxY + 4)
        XCTAssertTrue(app.buttons["portfolio.entry.NVDA"].isHittable)
        screenshot(app, "Portfolio - whole-page scroll")

        app.buttons["portfolio.tab.allTickers"].tap()
        let trending = app.staticTexts["portfolio.trending.title"]
        XCTAssertTrue(trending.waitForExistence(timeout: 5))
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "portfolio.ticker."))
        XCTAssertGreaterThan(rows.count, 0)
        let topTicker = rows.firstMatch.identifier
        XCTAssertEqual(rows.matching(identifier: topTicker).count, 1)
        XCTAssertLessThan(trending.frame.maxY, rows.firstMatch.frame.minY)
        screenshot(app, "Portfolio - trending directory")
        rows.firstMatch.tap()
        XCTAssertTrue(app.buttons["detail.back"].waitForExistence(timeout: 5))
        app.buttons["detail.back"].tap()
        XCTAssertTrue(app.buttons["portfolio.tab.allTickers"].isSelected)

        let search = app.textFields["portfolio.ticker-search"]
        search.tap()
        search.typeText("AAPL")
        XCTAssertTrue(app.buttons["portfolio.ticker.AAPL"].waitForExistence(timeout: 5))
        XCTAssertFalse(trending.exists)
        app.buttons["portfolio.tab.holdings"].tap()
        for _ in 0..<3 { page.swipeDown() }
        XCTAssertTrue(app.buttons["portfolio.period.1W"].isHittable)
        XCTAssertTrue(app.buttons["portfolio.period.1W"].isSelected)
    }

    func testTabsSwipeWithoutReplacingSummaryAndChartSupportsPeriods() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reset-state", "--ui-scenario=loaded", "--ui-trading-fixture",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let portfolio = app.descendants(matching: .any)["app.tab.portfolio"]
        XCTAssertTrue(portfolio.waitForExistence(timeout: 8))
        portfolio.tap()
        let holdings = app.buttons["portfolio.tab.holdings"]
        XCTAssertTrue(holdings.waitForExistence(timeout: 5))
        XCTAssertTrue(holdings.isSelected)
        XCTAssertFalse(app.segmentedControls["portfolio.section-picker"].exists)
        let chart = app.descendants(matching: .any)["portfolio.value-chart"]
        XCTAssertTrue(chart.exists)
        let chartFrame = chart.frame
        app.buttons["portfolio.period.1W"].tap()
        XCTAssertTrue(app.buttons["portfolio.period.1W"].isSelected)
        app.buttons["portfolio.period.All"].tap()

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.69))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.69))
        start.press(forDuration: 0.05, thenDragTo: end)
        let all = app.buttons["portfolio.tab.allTickers"]
        expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: all)
        waitForExpectations(timeout: 3)
        XCTAssertTrue(app.textFields["portfolio.ticker-search"].exists)
        XCTAssertEqual(chart.frame.minY, chartFrame.minY, accuracy: 1)
        let search = app.textFields["portfolio.ticker-search"]
        search.tap()
        search.typeText("AAPL")
        XCTAssertTrue(app.buttons["portfolio.ticker.AAPL"].isHittable)
        app.buttons["portfolio.tab.watchlist"].tap()
        XCTAssertTrue(app.buttons["portfolio.tab.watchlist"].isSelected)
        XCTAssertTrue(chart.exists)
        end.press(forDuration: 0.05, thenDragTo: start)
        XCTAssertTrue(app.buttons["portfolio.tab.watchlist"].isSelected)
        start.press(forDuration: 0.05, thenDragTo: end)
        expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: holdings)
        waitForExpectations(timeout: 3)
        let holdingsPage = app.scrollViews["portfolio.page.holdings"]
        for _ in 0..<4 {
            if app.buttons["portfolio.account.app"].isHittable { break }
            holdingsPage.swipeDown()
        }
        app.buttons["portfolio.account.app"].tap()
        XCTAssertTrue(app.buttons["portfolio.account.app"].isSelected)
        XCTAssertTrue(chart.exists)
        XCTAssertTrue(app.staticTexts["portfolio.app.cash"].exists)
    }

    private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
