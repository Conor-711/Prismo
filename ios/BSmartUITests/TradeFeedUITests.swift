import XCTest

final class TradeFeedUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testDiscoverIsRankingOnly() {
        let app = launch(layoutPreview: true)
        app.buttons["app.tab.feed"].tap()

        XCTAssertEqual(app.buttons["app.tab.feed"].label, "Leaderboard")
        XCTAssertTrue(app.navigationBars["Leaderboard"].waitForExistence(timeout: 8))
        XCTAssertTrue(element("discover.ability-leaderboard", in: app).waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Mock score ranking"].exists)
        XCTAssertTrue(element("discover.ability.mock-disclaimer", in: app).exists)
        XCTAssertTrue(actorRows(in: app).firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Full ranking"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Leaderboard"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertFalse(app.buttons["discover.tab.popular"].exists)
        XCTAssertFalse(app.buttons["discover.tab.latest"].exists)
        XCTAssertFalse(app.buttons["discover.tab.ranking"].exists)
        XCTAssertFalse(element("feed.popular", in: app).exists)
        XCTAssertFalse(element("feed.row.71000000-0000-0000-0000-000000000001", in: app).exists)
    }

    func testRankingFiltersAndDetailStayMockLabeled() {
        let app = launch(layoutPreview: true)
        app.buttons["app.tab.feed"].tap()
        let politicians = app.buttons["discover.ability.filter.politician"]
        XCTAssertTrue(politicians.waitForExistence(timeout: 8))
        politicians.tap()
        XCTAssertTrue(politicians.isSelected)
        let row = actorRows(in: app).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.tap()
        XCTAssertTrue(app.staticTexts["Mock score"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Mock scores for preview only; not actual investment results or return forecasts"].exists)
        XCTAssertFalse(app.staticTexts["Observation days"].exists)
    }

    func testSignedOutChineseDiscoverStillShowsRanking() {
        let app = launch(chinese: true)
        app.buttons["app.tab.feed"].tap()
        XCTAssertEqual(app.buttons["app.tab.feed"].label, "排行榜")
        XCTAssertTrue(app.navigationBars["排行榜"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["模拟能力榜单"].waitForExistence(timeout: 8))
        XCTAssertTrue(actorRows(in: app).firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["登录后查看真实交易"].exists)
        XCTAssertFalse(app.buttons["discover.tab.popular"].exists)
        XCTAssertFalse(app.buttons["discover.tab.latest"].exists)
    }

    func testProfileHasNoAssistantEntry() {
        let app = launch()
        XCTAssertFalse(app.buttons["app.tab.ai"].exists)
        app.buttons["app.tab.portfolio"].tap()
        XCTAssertTrue(app.staticTexts["profile.nickname"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["profile.ai.open"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["ai.screen"].exists)
        XCTAssertTrue(app.buttons["app.tab.feed"].exists)
    }

    private func actorRows(in app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "discover.ability.actor."))
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func launch(layoutPreview: Bool = false, chinese: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reset-state", "--ui-scenario=loaded", "--ui-trading-fixture",
                               "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)",
                               "-AppleLocale", chinese ? "zh_CN" : "en_US"]
        if layoutPreview { app.launchArguments.append("--ui-feed-layout-preview") }
        app.launch()
        XCTAssertTrue(app.buttons["app.tab.feed"].waitForExistence(timeout: 10))
        return app
    }
}
