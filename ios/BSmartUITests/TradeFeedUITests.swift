import XCTest

final class TradeFeedUITests: XCTestCase {
    private let first = "70000000-0000-0000-0000-000000000001"
    override func setUpWithError() throws { continueAfterFailure = false }

    func testExplicitDemoWorksWithoutLiveFeedAndDoesNotOpenAnOrder() {
        let app = launch(fixture: false)
        app.buttons["app.tab.feed"].tap()
        XCTAssertTrue(element("feed.unavailable", app).waitForExistence(timeout: 8))
        app.buttons["feed.demo.toggle"].tap()
        let demoID = "71000000-0000-0000-0000-000000000001"
        XCTAssertTrue(app.buttons["feed.user." + demoID].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Feed · Demo"].exists)
        XCTAssertFalse(element("feed.unavailable", app).exists)
        app.buttons["feed.user." + demoID].tap()
        XCTAssertTrue(element("feed.profile.nickname", app).waitForExistence(timeout: 5))
        XCTAssertEqual(element("feed.profile.nickname", app).label, "Casey")
        app.buttons["detail.back"].tap()
        for choice in ["short.100", "short.500", "long.500", "long.100"] {
            app.buttons["feed.quick.\(demoID).\(choice)"].tap()
            XCTAssertTrue(element("feed.demo.preview", app).waitForExistence(timeout: 5))
            XCTAssertEqual(element("feed.demo.notional", app).label, "$" + choice.split(separator: ".")[1])
            XCTAssertFalse(element("trade.live.screen", app).exists)
            XCTAssertFalse(element("feed.quick.filled", app).exists)
            app.buttons["feed.demo.done"].tap()
        }
        let more = app.buttons["feed.more"]
        for _ in 0..<5 where !more.isHittable { app.swipeUp() }
        XCTAssertTrue(more.isHittable)
        more.tap()
        let last = element("feed.row.71000000-0000-0000-0000-000000000006", app)
        for _ in 0..<5 where !last.exists { app.swipeUp() }
        XCTAssertTrue(last.exists)
        app.buttons["feed.demo.toggle"].tap()
        XCTAssertTrue(element("feed.unavailable", app).waitForExistence(timeout: 5))
        XCTAssertFalse(element("feed.row." + demoID, app).exists)
    }

    func testAssistantExpandsFromProfileAndRestoresTabsRepeatedly() {
        let app = launch()
        XCTAssertFalse(app.buttons["app.tab.ai"].exists)
        app.buttons["app.tab.portfolio"].tap()
        let launcher = app.buttons["profile.ai.open"]
        XCTAssertTrue(launcher.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(launcher.frame.midX, app.frame.midX)
        XCTAssertLessThan(launcher.frame.maxY, app.buttons["app.tab.portfolio"].frame.minY)
        for _ in 0..<3 {
            launcher.tap()
            XCTAssertTrue(app.buttons["ai.back"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["app.tab.feed"].exists)
            app.buttons["ai.back"].tap()
            XCTAssertTrue(app.buttons["app.tab.feed"].waitForExistence(timeout: 5))
            XCTAssertTrue(launcher.isHittable)
        }
    }

    func testFeedFieldDestinationsAndChronology() {
        let app = launch()
        app.buttons["app.tab.feed"].tap()
        XCTAssertTrue(element("feed.row." + first, app).waitForExistence(timeout: 8))
        XCTAssertLessThan(element("feed.row." + first, app).frame.minY,
                          element("feed.row.70000000-0000-0000-0000-000000000002", app).frame.minY)
        for (field, destination) in [("user", "feed.profile.screen"), ("author", "smart.account.detail.section"),
                                     ("opinion", "smart.account.evidence.detail"), ("ticker", "ticker-intelligence.NVDA")] {
            let button = app.buttons["feed.\(field).\(first)"]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            button.tap()
            XCTAssertTrue(element(destination, app).waitForExistence(timeout: 8))
            app.buttons["detail.back"].firstMatch.tap()
            XCTAssertTrue(app.buttons["feed.opinion." + first].waitForExistence(timeout: 6))
        }
    }

    func testQuickButtonsOpenRealConfirmationWithoutAutomaticPaperFill() {
        let app = launch()
        app.buttons["app.tab.feed"].tap()
        let choices = ["short.100", "short.500", "long.500", "long.100"]
        let buttons = choices.map { app.buttons["feed.quick.\(first).\($0)"] }
        XCTAssertTrue(buttons[0].waitForExistence(timeout: 8))
        for index in 1..<buttons.count { XCTAssertLessThan(buttons[index-1].frame.midX, buttons[index].frame.midX) }
        for choice in choices {
            let button = app.buttons["feed.quick.\(first).\(choice)"]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            button.tap()
            XCTAssertTrue(element("trade.live.screen", app).waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["trade.live.wallet"].exists)
            XCTAssertFalse(element("feed.quick.filled", app).exists)
            XCTAssertFalse(element("trade.order.done", app).exists)
            app.buttons["feed.live.close"].tap()
            XCTAssertTrue(app.buttons["app.tab.feed"].waitForExistence(timeout: 5))
        }
    }

    func testUnavailableNeverShowsDemoTrades() {
        let app = launch(fixture: false)
        app.buttons["app.tab.feed"].tap()
        XCTAssertTrue(element("feed.unavailable", app).waitForExistence(timeout: 8))
        XCTAssertFalse(element("feed.row." + first, app).exists)
        XCTAssertFalse(element("feed.empty", app).exists)
    }

    private func launch(fixture: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reset-state", "--ui-scenario=loaded", "--ui-trading-fixture",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if fixture { app.launchArguments.append("--ui-trade-feed-fixture") }
        app.launch()
        XCTAssertTrue(app.buttons["app.tab.feed"].waitForExistence(timeout: 10))
        return app
    }
    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }
}
