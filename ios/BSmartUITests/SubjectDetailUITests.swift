import XCTest

final class SubjectDetailUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testOptionHistoryHasOneAssetModuleShortInterpretationAndSourceTradeEntry() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reset-state", "--ui-scenario=loaded", "--ui-trading-fixture",
                               "--ui-subject-option-fixture",
                               "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        verifyOptionHistory(in: app)
    }

    func testDeviceSubjectAndTraderDetailsWithoutResetOrTrading() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Keeps the connected iPhone's real account intact; no trading or transfers.")
        #else
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["app.tab.today"].waitForExistence(timeout: 60))
        app.buttons["app.tab.today"].tap()
        app.buttons["today.tab.activity"].tap()
        verifyOptionHistory(in: app)
        app.buttons["detail.back"].firstMatch.tap()
        let sources = app.scrollViews["smart-updates.sources"]
        sources.swipeRight(); sources.swipeRight()
        let native = app.buttons["smart-updates.platform.bsmart"]
        for _ in 0..<3 where !native.isHittable { sources.swipeRight() }
        XCTAssertTrue(native.isHittable)
        native.tap()
        let trader = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "subject.account.bsmart:")).firstMatch
        XCTAssertTrue(trader.waitForExistence(timeout: 20))
        trader.tap()
        XCTAssertTrue(element("smart.account.detail", app).waitForExistence(timeout: 8))
        let equity = app.staticTexts["feed.profile.equity-value"]
        for _ in 0..<4 where !equity.isHittable { app.swipeUp() }
        XCTAssertTrue(equity.waitForExistence(timeout: 40), app.debugDescription)
        XCTAssertFalse(equity.label.contains("--"))
        XCTAssertTrue(element("feed.profile.positions", app).exists)
        XCTAssertTrue(app.buttons["feed.profile.message"].exists)
        XCTAssertTrue(app.buttons["smart.account.follow"].exists)
        app.buttons["detail.back"].firstMatch.tap()
        #endif
    }

    private func verifyOptionHistory(in app: XCUIApplication) {
        let sources = app.scrollViews["smart-updates.sources"]
        XCTAssertTrue(sources.waitForExistence(timeout: 10))
        sources.swipeLeft()
        sources.swipeLeft()
        let celebrities = app.buttons["smart-updates.platform.celebrities"]
        XCTAssertTrue(celebrities.isHittable)
        celebrities.tap()
        let link = app.buttons.matching(identifier: "subject-activity.profile.celebrity:ken-griffin").firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 8), app.debugDescription)
        let page = app.scrollViews["today.page.activity"]
        for _ in 0..<12 where !link.isHittable { page.swipeUp() }
        XCTAssertTrue(link.isHittable, app.debugDescription)
        link.tap()
        XCTAssertTrue(element("subject.profile.detail.celebrity:ken-griffin", app).waitForExistence(timeout: 5))
        let eventID = "13f:e7a3878173bdc8ac1935"
        let card = element("subject.profile.event-card.\(eventID)", app)
        for _ in 0..<6 where !card.isHittable { app.swipeUp() }
        XCTAssertTrue(card.exists)
        XCTAssertEqual(card.staticTexts.matching(identifier: "TSLA").count, 1)
        XCTAssertEqual(card.descendants(matching: .any).matching(identifier: "feed.holding-asset.\(eventID)").count, 1)
        let sync = card.buttons["trade.open.tsla"]
        for _ in 0..<3 where !sync.isHittable { app.swipeUp() }
        XCTAssertTrue(sync.isHittable)
        XCTAssertFalse(card.staticTexts["同步标的，不复制期权"].exists)
        XCTAssertFalse(card.staticTexts["敞口解读"].exists)
        let asset = card.descendants(matching: .any).matching(identifier: "feed.holding-asset.\(eventID)").firstMatch
        let shortTitle = asset.staticTexts["subject.option-interpretation.title.\(eventID)"]
        XCTAssertEqual(shortTitle.label, "看多敞口减少")
        XCTAssertLessThanOrEqual(asset.frame.height, 150)
        let logo = asset.images.matching(NSPredicate(format: "label == %@", "TSLA 标的")).firstMatch
        let ticker = asset.staticTexts.matching(NSPredicate(format: "label == %@", "TSLA")).firstMatch
        XCTAssertTrue(logo.exists)
        XCTAssertLessThanOrEqual(abs(logo.frame.minY - ticker.frame.minY), 8)
        XCTAssertLessThanOrEqual(asset.staticTexts["TESLA INC"].frame.maxY, shortTitle.frame.minY)
        XCTAssertFalse(asset.staticTexts["COM"].exists)
        let interpretation = asset.buttons["subject.option-interpretation.info.\(eventID)"]
        XCTAssertTrue(interpretation.exists)
        XCTAssertGreaterThanOrEqual(interpretation.frame.width, 43.99)
        XCTAssertGreaterThanOrEqual(interpretation.frame.height, 43.99)
        XCTAssertLessThanOrEqual(shortTitle.frame.maxY + 12, sync.frame.minY)
        XCTAssertFalse(card.staticTexts["Call 持仓减少，不等于转为看空。"].exists)
        interpretation.tap()
        XCTAssertTrue(element("subject.option-interpretation.explanation.\(eventID)", app).waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Call 持仓减少，不等于转为看空。"].exists)
        app.buttons["subject.option-interpretation.close.\(eventID)"].tap()
        XCTAssertTrue(element("subject.option-interpretation.explanation.\(eventID)", app).waitForNonExistence(timeout: 3))
        sync.tap()
        XCTAssertTrue(element("trade.live.screen", app).waitForExistence(timeout: 30), app.debugDescription)
        let marketPicker = app.buttons["trade.market-picker"]
        XCTAssertTrue(marketPicker.waitForExistence(timeout: 40), app.debugDescription)
        XCTAssertTrue(marketPicker.label.contains("TSLA"))
        XCTAssertTrue(app.buttons["trade.close"].exists)
        app.buttons["trade.close"].tap()
        XCTAssertTrue(element("subject.profile.detail.celebrity:ken-griffin", app).exists)
    }

    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
}
