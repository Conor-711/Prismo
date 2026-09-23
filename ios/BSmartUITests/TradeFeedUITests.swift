import XCTest

final class TradeFeedUITests: XCTestCase {
    private let first = "70000000-0000-0000-0000-000000000001"
    override func setUpWithError() throws { continueAfterFailure = false }

    func testCompactTradeActionKeepsTickerAndNeverPreselectsAnAmount() {
        let app = launch(fixture: false, layoutPreview: true)
        app.buttons["app.tab.feed"].tap()
        app.buttons["discover.tab.latest"].tap()
        let id = "71000000-0000-0000-0000-000000000001"
        let ticker = app.buttons["feed.ticker." + id]
        let trade = app.buttons["feed.quick.\(id).trade"]
        XCTAssertTrue(trade.waitForExistence(timeout: 8))
        for _ in 0..<3 where !trade.isHittable { app.swipeUp() }
        XCTAssertTrue(ticker.isHittable && trade.isHittable)
        XCTAssertEqual(trade.label, "Trade NVDA")
        XCTAssertGreaterThanOrEqual(trade.frame.height, 44)
        XCTAssertLessThan(ticker.frame.maxY, trade.frame.minY)
        XCTAssertFalse(app.buttons["feed.trade.ticker." + id].exists)
        XCTAssertFalse(app.buttons["feed.quick.\(id).long"].exists)
        XCTAssertFalse(app.buttons["feed.quick.\(id).short"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "compact-trade-feed-card"; attachment.lifetime = .keepAlways; add(attachment)
        trade.tap()
        XCTAssertTrue(element("feed.demo.preview", app).waitForExistence(timeout: 5))
        XCTAssertFalse(element("feed.demo.notional", app).exists)
        XCTAssertFalse(element("trade.live.screen", app).exists)
        XCTAssertFalse(element("trade.order.done", app).exists)
        app.buttons["feed.demo.done"].tap()
    }

    func testCompactTradeActionChineseLargeText() {
        let app = launch(fixture: false, layoutPreview: true, chineseLargeText: true)
        app.buttons["app.tab.feed"].tap()
        app.buttons["discover.tab.latest"].tap()
        let id = "71000000-0000-0000-0000-000000000001"
        let ticker = app.buttons["feed.ticker." + id]
        let trade = app.buttons["feed.quick.\(id).trade"]
        XCTAssertTrue(trade.waitForExistence(timeout: 8))
        for _ in 0..<3 where !trade.isHittable { app.swipeUp() }
        XCTAssertTrue(ticker.isHittable && trade.isHittable)
        XCTAssertTrue(trade.label.contains("交易"))
        XCTAssertGreaterThanOrEqual(trade.frame.height, 44)
        XCTAssertLessThan(ticker.frame.maxY, trade.frame.minY)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "compact-trade-feed-card-zh-large-text"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testPopularModeSwitchesWithoutCreatingTrades() {
        let app = launch(fixture: false, layoutPreview: true)
        app.buttons["app.tab.feed"].tap()
        XCTAssertEqual(app.buttons["app.tab.feed"].label, "Discover")
        XCTAssertTrue(app.navigationBars["Discover · Demo"].exists)
        let popular = app.buttons["discover.tab.popular"]
        let latest = app.buttons["discover.tab.latest"]
        XCTAssertTrue(popular.waitForExistence(timeout: 8))
        XCTAssertTrue(popular.isSelected)
        XCTAssertLessThan(popular.frame.minX, latest.frame.minX)
        XCTAssertFalse(app.segmentedControls["feed.mode"].exists)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "feed.popular.opinion.")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        XCTAssertFalse(element("opinion.traders.split", app).exists)
        XCTAssertFalse(element("trade.live.screen", app).exists)
        swipeDiscover(app, from: "popular", forward: true)
        XCTAssertTrue(latest.isSelected)
        XCTAssertTrue(element("feed.row.71000000-0000-0000-0000-000000000001", app).waitForExistence(timeout: 8))
        swipeDiscover(app, from: "latest", forward: false)
        XCTAssertTrue(popular.isSelected)
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        latest.tap()
        XCTAssertTrue(latest.isSelected)
        popular.tap()
        XCTAssertTrue(popular.isSelected)
        XCTAssertFalse(element("trade.order.done", app).exists)
    }

    func testPopularRankingsPreviewMoreAndFilters() {
        let app = launch(fixture: false, layoutPreview: true)
        app.buttons["app.tab.feed"].tap()
        let opinionRows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "feed.popular.opinion."))
        XCTAssertTrue(opinionRows.firstMatch.waitForExistence(timeout: 8))
        XCTAssertLessThanOrEqual(opinionRows.count, 3)
        let more = app.buttons["discovery.more.opinions"]
        XCTAssertGreaterThan(more.frame.minY, opinionRows.element(boundBy: opinionRows.count - 1).frame.maxY)
        for _ in 0..<4 where !more.isHittable { app.swipeUp() }
        XCTAssertTrue(more.isHittable, app.debugDescription)
        more.tap()
        XCTAssertTrue(app.navigationBars["Trending opinions"].waitForExistence(timeout: 5))
        XCTAssertTrue(opinionRows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(element("opinion.traders.split", app).exists)
        app.buttons["discovery.rankings.sort"].tap()
        app.buttons["discovery.option.sort.volume"].tap()
        XCTAssertTrue(app.buttons["discovery.rankings.sort"].label.contains("Trading volume"))
        app.buttons["discovery.rankings.window"].tap()
        app.buttons["discovery.option.window.1d"].tap()
        XCTAssertTrue(app.buttons["discovery.rankings.window"].label.contains("24 hours"))
        XCTAssertTrue(opinionRows.firstMatch.waitForExistence(timeout: 5))
        app.buttons["detail.back"].tap()
        XCTAssertTrue(app.buttons["discovery.more.opinions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["discovery.rankings.window"].label.contains("Past 7 days"))
        let investors = app.buttons["discovery.more.investors"]
        for _ in 0..<6 where !investors.isHittable { app.swipeUp() }
        XCTAssertTrue(investors.isHittable)
        investors.tap()
        XCTAssertTrue(app.navigationBars["Trending investors"].waitForExistence(timeout: 5))
        let investorRows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "feed.popular.investor."))
        XCTAssertTrue(investorRows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(element("trade.live.screen", app).exists)
    }

    func testOpinionShareOpensInAppChatPicker() {
        let app = launch(fixture: false, layoutPreview: true)
        app.buttons["app.tab.feed"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "feed.popular.opinion.")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.tap()
        let share = app.buttons["opinion.share"]
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(share.frame.width, 44)
        XCTAssertGreaterThanOrEqual(share.frame.height, 44)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "in-app-share-button"; screenshot.lifetime = .keepAlways; add(screenshot)
        share.tap()
        XCTAssertTrue(element("chat.share.preview", app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("chat.shared-avatar", app).exists)
        XCTAssertTrue(element("chat.shared-logo", app).exists)
        XCTAssertTrue(app.navigationBars["Share to chat"].exists)
        XCTAssertFalse(app.otherElements["UIActivityViewController"].exists)
        let preview = XCTAttachment(screenshot: app.screenshot())
        preview.name = "in-app-share-preview"; preview.lifetime = .keepAlways; add(preview)
    }

    func testInvestorSharePreviewShowsAvatarAndTickerLogo() {
        let app = launch(fixture: false, layoutPreview: true)
        app.buttons["app.tab.feed"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "feed.popular.investor.")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.tap()
        let share = app.buttons["smart.account.share"]
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        share.tap()
        XCTAssertTrue(element("chat.share.preview", app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("chat.shared-avatar", app).exists)
        XCTAssertTrue(element("chat.shared-logo", app).exists)
    }

    func testDiscoverChineseLargeTextAndSignedOutState() {
        let app = launch(fixture: false, chineseLargeText: true)
        app.buttons["app.tab.feed"].tap()
        XCTAssertEqual(app.buttons["app.tab.feed"].label, "发现")
        XCTAssertTrue(app.navigationBars["发现"].exists)
        let popular = app.buttons["discover.tab.popular"]
        let latest = app.buttons["discover.tab.latest"]
        XCTAssertTrue(popular.waitForExistence(timeout: 5))
        XCTAssertEqual(popular.label, "热门")
        XCTAssertEqual(latest.label, "最近成交")
        XCTAssertTrue(popular.isSelected)
        for tab in [popular, latest] {
            XCTAssertTrue(tab.isHittable)
            XCTAssertGreaterThanOrEqual(tab.frame.height, 44)
            XCTAssertGreaterThanOrEqual(tab.frame.minX, app.frame.minX)
            XCTAssertLessThanOrEqual(tab.frame.maxX, app.frame.maxX)
        }
        // Accessibility can expand the hit frame of the shorter Popular title.
        XCTAssertGreaterThanOrEqual(latest.frame.minX - popular.frame.maxX, 28)
        XCTAssertTrue(app.buttons["登录后查看真实交易"].exists)
        swipeDiscover(app, from: "popular", forward: true)
        XCTAssertTrue(latest.isSelected)
        swipeDiscover(app, from: "latest", forward: false)
        XCTAssertTrue(popular.isSelected)
        XCTAssertFalse(element("feed.row." + first, app).exists)
        XCTAssertFalse(app.buttons["feed.demo.toggle"].exists)
    }

    private func swipeDiscover(_ app: XCUIApplication, from section: String, forward: Bool) {
        let page = app.scrollViews["discover.page.\(section)"]
        let start = page.coordinate(withNormalizedOffset: CGVector(dx: forward ? 0.85 : 0.15, dy: 0.4))
        let end = page.coordinate(withNormalizedOffset: CGVector(dx: forward ? 0.15 : 0.85, dy: 0.4))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

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
        app.buttons["feed.quick.\(demoID).trade"].tap()
        XCTAssertTrue(element("feed.demo.preview", app).waitForExistence(timeout: 5))
        XCTAssertFalse(element("feed.demo.notional", app).exists)
        XCTAssertFalse(element("trade.live.screen", app).exists)
        XCTAssertFalse(element("feed.quick.filled", app).exists)
        app.buttons["feed.demo.done"].tap()
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
        let app = launch(fixture: false, layoutPreview: true)
        app.buttons["app.tab.feed"].tap()
        app.buttons["discover.tab.latest"].tap()
        let id = "71000000-0000-0000-0000-000000000001"
        XCTAssertTrue(element("feed.row." + id, app).waitForExistence(timeout: 8))
        XCTAssertLessThan(element("feed.row." + id, app).frame.minY,
                          element("feed.row.71000000-0000-0000-0000-000000000002", app).frame.minY)
        for (field, destination) in [("user", "feed.profile.screen"), ("author", "smart.account.detail"),
                                     ("opinion", "smart.account.evidence.detail"), ("ticker", "ticker-intelligence.NVDA")] {
            let button = app.buttons["feed.\(field).\(id)"]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            button.tap()
            XCTAssertTrue(element(destination, app).waitForExistence(timeout: 8))
            app.buttons["detail.back"].firstMatch.tap()
            XCTAssertTrue(app.buttons["feed.opinion." + id].waitForExistence(timeout: 6))
        }
    }

    func testSingleTradeButtonKeepsHistoricalSideInDemoPreview() {
        let app = launch(fixture: false, layoutPreview: true)
        app.buttons["app.tab.feed"].tap()
        app.buttons["discover.tab.latest"].tap()
        let id = "71000000-0000-0000-0000-000000000002"
        let button = app.buttons["feed.quick.\(id).trade"]
        XCTAssertTrue(button.waitForExistence(timeout: 8))
        for _ in 0..<3 where !button.isHittable { app.swipeUp() }
        XCTAssertEqual(button.label, "Trade MSFT")
        XCTAssertFalse(app.buttons["feed.quick.\(id).long"].exists)
        XCTAssertFalse(app.buttons["feed.quick.\(id).short"].exists)
        button.tap()
        XCTAssertTrue(element("feed.demo.preview", app).waitForExistence(timeout: 5))
        XCTAssertEqual(element("feed.demo.direction", app).label, "Short MSFT")
        XCTAssertFalse(element("trade.live.screen", app).exists)
        XCTAssertFalse(element("trade.order.done", app).exists)
        app.buttons["feed.demo.done"].tap()
        XCTAssertTrue(app.buttons["app.tab.feed"].waitForExistence(timeout: 5))
    }

    func testUnavailableNeverShowsDemoTrades() {
        let app = launch(fixture: false)
        app.buttons["app.tab.feed"].tap()
        XCTAssertTrue(element("feed.unavailable", app).waitForExistence(timeout: 8))
        XCTAssertFalse(element("feed.row." + first, app).exists)
        XCTAssertFalse(element("feed.empty", app).exists)
    }

    private func launch(fixture: Bool = true, layoutPreview: Bool = false, chineseLargeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reset-state", "--ui-scenario=loaded", "--ui-trading-fixture",
                               "-AppleLanguages", chineseLargeText ? "(zh-Hans)" : "(en)",
                               "-AppleLocale", chineseLargeText ? "zh_CN" : "en_US"]
        if chineseLargeText {
            app.launchArguments += ["--ui-appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"]
        }
        if fixture { app.launchArguments.append("--ui-trade-feed-fixture") }
        if layoutPreview { app.launchArguments.append("--ui-feed-layout-preview") }
        app.launch()
        XCTAssertTrue(app.buttons["app.tab.feed"].waitForExistence(timeout: 10))
        return app
    }
    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }
}
