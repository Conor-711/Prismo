import XCTest

final class MarketChartUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testDiscoveryHomeLeavesMarketChartInTickerDetail() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["discovery.heading"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.descendants(matching: .any)["today.price-chart"].exists)
        app.descendants(matching: .any)["app.tab.portfolio"].tap()
        app.descendants(matching: .any)["portfolio.entry.NVDA"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["hyperliquid.chart"].waitForExistence(timeout: 8))
        app.buttons["trade.chart-style"].tap()
        app.buttons["Candlestick chart"].tap()
        capture(app, "Ticker OHLC candles without posts")
    }

    func testCompactDockCandlesAndWalletGateInLightMode() {
        let app = launch(appearance: "light")
        app.descendants(matching: .any)["app.tab.portfolio"].tap()
        app.buttons["portfolio.account.switch"].tap()
        app.descendants(matching: .any)["portfolio.entry.NVDA"].tap()
        let short = app.buttons["trade.open.nvda.short"]
        let long = app.buttons["trade.open.nvda"]
        XCTAssertTrue(short.waitForExistence(timeout: 8))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"), object: long
        )], timeout: 5), .completed, app.debugDescription)
        XCTAssertGreaterThanOrEqual(short.frame.height, 44)
        XCTAssertLessThanOrEqual(short.frame.height, 46)
        XCTAssertEqual(short.frame.height, long.frame.height)
        app.buttons["trade.chart-style"].tap()
        app.buttons["Candlestick chart"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["hyperliquid.chart"].exists)
        short.tap()
        XCTAssertTrue(app.buttons["trade.live.wallet"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.descendants(matching: .any)["trading-order.submit"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["trade.composer"].exists)
        XCTAssertTrue(app.buttons["trade.close"].isHittable)
        XCTAssertFalse(app.buttons["app.tab.portfolio"].isHittable)
        app.buttons["trade.close"].tap()
        XCTAssertTrue(short.waitForExistence(timeout: 5))
    }

    private func launch(appearance: String = "dark") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reset-state", "--ui-scenario=market-history", "--ui-trading-fixture",
                               "--ui-appearance", appearance, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
