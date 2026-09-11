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

    func testCompactDockAndTradeSheetCandlesInLightMode() {
        let app = launch(appearance: "light")
        app.descendants(matching: .any)["app.tab.portfolio"].tap()
        app.descendants(matching: .any)["portfolio.entry.NVDA"].tap()
        let short = app.buttons["trade.open.nvda.short"]
        let long = app.buttons["trade.open.nvda"]
        XCTAssertTrue(short.waitForExistence(timeout: 8))
        XCTAssertTrue(long.isHittable)
        XCTAssertGreaterThanOrEqual(short.frame.height, 44)
        XCTAssertLessThanOrEqual(short.frame.height, 46)
        XCTAssertEqual(short.frame.height, long.frame.height)
        app.buttons["trade.chart-style"].tap()
        app.buttons["Candlestick chart"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["hyperliquid.chart"].exists)
        capture(app, "Ticker candles and compact dock light")
        short.tap()
        XCTAssertTrue(app.buttons["trade.mode.chart"].waitForExistence(timeout: 8))
        app.buttons["trade.mode.chart"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["hyperliquid.chart"].exists)
        capture(app, "Quick order candlesticks light")
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
