import XCTest

final class PriceChartInteractionUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testTradeChartPinchPanInspectionResetAndRangeChange() {
        let app = launch(scenario: "market-history")
        app.descendants(matching: .any)["app.tab.portfolio"].tap()
        app.descendants(matching: .any)["portfolio.entry.NVDA"].tap()
        let chart = app.descendants(matching: .any)["hyperliquid.chart"]
        XCTAssertTrue(chart.waitForExistence(timeout: 8))
        app.buttons["trade.chart-style"].tap()
        app.buttons["Candlestick chart"].tap()
        verifyInteractions("trade.price-chart", in: app, pinch: true)
        app.buttons["trade.price-chart.zoom-in"].tap()
        app.buttons["trade.range.1W"].tap()
        XCTAssertTrue(app.buttons["trade.price-chart.zoom-out"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["trade.price-chart.zoom-out"].isEnabled)
    }

    func testRepresentativeAndOpinionEvidenceShareInteractiveChart() {
        let app = launch()
        app.descendants(matching: .any)["app.tab.smart"].tap()
        let author = app.descendants(matching: .any)["smart.account.row.first"]
        XCTAssertTrue(author.waitForExistence(timeout: 8))
        author.tap()
        XCTAssertTrue(app.descendants(matching: .any)["smart.account.detail"].waitForExistence(timeout: 5))
        revealChart("account.work.chart", in: app)
        verifyInteractions("account.work.chart", in: app, pinch: false)
        let marker = app.buttons["account.work.marker.1"]
        XCTAssertTrue(marker.isHittable)
        marker.tap()
        XCTAssertTrue(app.buttons["account.work.opinion.1"].isSelected)
        app.buttons["account.work.marker.0"].tap()
        let evidence = app.descendants(matching: .any).matching(identifier: "account.work.evidence").firstMatch
        reveal(evidence, in: app)
        evidence.tap()
        XCTAssertTrue(app.descendants(matching: .any)["smart.account.evidence.detail"].waitForExistence(timeout: 5))
        let timeline = app.buttons["opinion.price-timeline.toggle"]
        XCTAssertTrue(timeline.exists)
        XCTAssertFalse(app.descendants(matching: .any)["opinion.evidence.chart.plot"].exists)
        reveal(timeline, in: app)
        timeline.tap()
        revealChart("opinion.evidence.chart", in: app)
        verifyInteractions("opinion.evidence.chart", in: app, pinch: true)
        XCTAssertTrue(app.buttons["opinion.evidence.marker.0"].exists)
    }

    func testSmartMoneyEntriesUseSameControlsInLightMode() {
        let app = launch(appearance: "light")
        app.descendants(matching: .any)["app.tab.smart"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Smart Money")).firstMatch.tap()
        let account = app.descendants(matching: .any)["smart.money.row.first"]
        XCTAssertTrue(account.waitForExistence(timeout: 5))
        account.tap()
        revealChart("money.evidence.chart", in: app)
        verifyInteractions("money.evidence.chart", in: app, pinch: false)
        XCTAssertTrue(app.buttons["money.evidence.marker.0"].firstMatch.exists)
    }

    private func verifyInteractions(_ id: String, in app: XCUIApplication, pinch: Bool) {
        let plot = app.descendants(matching: .any).matching(identifier: "\(id).plot").firstMatch
        XCTAssertTrue(plot.isHittable)
        let original = plot.value as? String
        XCTAssertNotNil(original)
        if pinch { plot.pinch(withScale: 2, velocity: 1) }
        else { app.buttons["\(id).zoom-in"].firstMatch.tap() }
        let zoomed = plot.value as? String
        XCTAssertNotEqual(zoomed, original, "Zoom must change the visible time window")
        let start = plot.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.8))
        let end = plot.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.8))
        start.press(forDuration: 0.01, thenDragTo: end)
        XCTAssertNotEqual(plot.value as? String, zoomed, "Horizontal drag must pan the chart")
        let date = app.staticTexts["\(id).date"].firstMatch
        let beforeInspection = date.label
        plot.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.8)).press(forDuration: 0.4)
        XCTAssertNotEqual(date.label, beforeInspection, "Long press must inspect a historical candle")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "\(id).ohlc").firstMatch.exists)
        app.buttons["\(id).reset"].firstMatch.tap()
        XCTAssertEqual(plot.value as? String, original)
        XCTAssertFalse(app.buttons["\(id).zoom-out"].firstMatch.isEnabled)
    }

    private func revealChart(_ id: String, in app: XCUIApplication) {
        let chart = app.descendants(matching: .any).matching(identifier: "\(id).plot").firstMatch
        for _ in 0..<18 {
            if chart.exists && chart.frame.minY > 150 && chart.frame.maxY < app.frame.height - 100 { return }
            if chart.exists && chart.frame.minY < 150 { app.swipeDown(velocity: .slow) }
            else { app.swipeUp(velocity: .slow) }
        }
        XCTFail("Chart not fully visible: \(id)\n\(app.debugDescription)")
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 {
            if element.isHittable && element.frame.minY > 130 && element.frame.maxY < app.frame.height - 140 { return }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.7))
                .press(forDuration: 0.01, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.4)))
        }
    }

    private func launch(scenario: String = "loaded", appearance: String = "dark") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reset-state", "--ui-scenario=\(scenario)", "--ui-trading-fixture",
                               "--ui-evidence-chart-fixture",
                               "--ui-appearance", appearance, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["app.tab.smart"].waitForExistence(timeout: 8))
        return app
    }
}
