import XCTest

final class PortfolioWorkspaceUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testWithdrawEntryIsBesideDepositAndRequiresAuthentication() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reset-state", "--ui-scenario=loaded", "--ui-trading-fixture",
            "--ui-appearance", "light", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let portfolio = app.buttons["app.tab.portfolio"]
        XCTAssertTrue(portfolio.waitForExistence(timeout: 10))
        portfolio.tap()
        let withdraw = app.buttons["portfolio.withdraw"]
        XCTAssertTrue(withdraw.waitForExistence(timeout: 5))
        let deposit = app.buttons["portfolio.deposit"]
        XCTAssertEqual(withdraw.frame.midY, deposit.frame.midY, accuracy: 2)
        XCTAssertGreaterThanOrEqual(withdraw.frame.minX, deposit.frame.maxX)
        withdraw.tap()
        XCTAssertTrue(app.buttons["withdraw.dismiss"].waitForExistence(timeout: 5))
        let signInButtons = app.buttons.matching(NSPredicate(format: "label == %@", "Sign in"))
        XCTAssertTrue(signInButtons.allElementsBoundByIndex.contains { $0.isHittable })
        XCTAssertFalse(app.buttons["withdraw.confirm"].exists)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == false"), object: app.buttons["app.tab.portfolio"]
        )], timeout: 5), .completed, app.debugDescription)
        app.buttons["withdraw.dismiss"].tap()
        XCTAssertTrue(withdraw.waitForExistence(timeout: 5))
    }

    func testWholePageScrollsAndDirectoryFiltersAndSorts() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reset-state", "--ui-scenario=loaded", "--ui-trading-fixture",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--ui-appearance", "light"]
        app.launch()
        let portfolio = app.buttons["app.tab.portfolio"]
        XCTAssertTrue(portfolio.waitForExistence(timeout: 8))
        portfolio.tap()
        app.buttons["portfolio.account.switch"].tap()
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
        let sort = app.buttons["portfolio.ticker-sort"]
        XCTAssertTrue(sort.waitForExistence(timeout: 5))
        XCTAssertTrue(sort.label.contains("Volume"))
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "portfolio.ticker."))
        XCTAssertGreaterThan(rows.count, 0)
        let topTicker = rows.firstMatch.identifier
        XCTAssertEqual(rows.matching(identifier: topTicker).count, 1)
        XCTAssertLessThan(sort.frame.maxY, rows.firstMatch.frame.minY)
        screenshot(app, "Portfolio - volume directory")
        sort.tap()
        XCTAssertTrue(app.buttons["portfolio.ticker-sort.gain"].waitForExistence(timeout: 3))
        app.buttons["portfolio.ticker-sort.gain"].tap()
        XCTAssertTrue(sort.label.contains("Top gainers"))
        sort.tap()
        app.buttons["portfolio.ticker-sort.loss"].tap()
        XCTAssertTrue(sort.label.contains("Top losers"))
        app.buttons["portfolio.ticker-filter.stocks"].tap()
        XCTAssertTrue(app.buttons["portfolio.ticker.NVDA"].exists)
        app.buttons["portfolio.ticker-filter.all"].tap()
        rows.firstMatch.tap()
        XCTAssertTrue(app.buttons["detail.back"].waitForExistence(timeout: 5))
        app.buttons["detail.back"].tap()
        XCTAssertTrue(app.buttons["portfolio.tab.allTickers"].isSelected)

        let search = app.textFields["portfolio.ticker-search"]
        search.tap()
        search.typeText("AAPL")
        XCTAssertTrue(app.buttons["portfolio.ticker.AAPL"].waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 1)
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
        app.buttons["portfolio.account.switch"].tap()
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

        let picker = app.descendants(matching: .any)["portfolio.section-picker"]
        let swipeY = min(picker.frame.maxY + 30, app.buttons["app.tab.portfolio"].frame.minY - 24)
        // Start clear of the floating assistant button at the right edge.
        let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.width * 0.7, dy: swipeY))
        let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.width * 0.15, dy: swipeY))
        start.press(forDuration: 0.05, thenDragTo: end)
        let all = app.buttons["portfolio.tab.allTickers"]
        expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: all)
        waitForExpectations(timeout: 3)
        XCTAssertTrue(app.textFields["portfolio.ticker-search"].exists)
        XCTAssertEqual(chart.frame.minY, chartFrame.minY, accuracy: 1)
        let search = app.textFields["portfolio.ticker-search"]
        search.tap()
        search.typeText("AAPL")
        let result = app.buttons["portfolio.ticker.AAPL"]
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == true"), object: result)], timeout: 5), .completed)
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
            if app.buttons["portfolio.account.switch"].isHittable { break }
            holdingsPage.swipeDown()
        }
        app.buttons["portfolio.account.switch"].tap()
        XCTAssertEqual(app.buttons["portfolio.account.switch"].value as? String, "Internal account")
        XCTAssertFalse(chart.exists)
        XCTAssertTrue(app.buttons["portfolio.deposit"].exists)
    }

    private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
