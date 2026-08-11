import XCTest

final class BSmartUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLoadedPortfolioOpensTodayWithoutBlockingLoader() {
        let app = launch(scenario: "loaded")

        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Portfolio status"].exists)
        XCTAssertFalse(app.staticTexts["Loading your portfolio"].exists)
    }

    func testWeightOnlyPortfolioUsesMonitoringSummaryInsteadOfZeroValue() {
        let app = launch(scenario: "weight-only")

        XCTAssertTrue(app.staticTexts["Portfolio monitor"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1 position"].exists)
        XCTAssertTrue(app.staticTexts["Declared allocation"].exists)
        XCTAssertTrue(app.staticTexts["35%"].exists)
        XCTAssertFalse(app.staticTexts["US$0"].exists)
        XCTAssertFalse(app.staticTexts["$0"].exists)
    }

    func testNoSignalStateRemainsInsideToday() {
        let app = launch(scenario: "no-signals")

        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No important changes"].waitForExistence(timeout: 2))
    }

    func testInitialFailureOffersRetry() {
        let app = launch(scenario: "error")

        XCTAssertTrue(app.staticTexts["Unable to load bSmart"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Try again"].exists)
    }

    func testSlowInitialLoadUsesDedicatedLoadingState() {
        let app = launch(scenario: "loading")

        XCTAssertTrue(app.staticTexts["Loading your portfolio"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Today"].exists)
    }

    func testDailyBriefOpensInsideToday() {
        let app = launch(scenario: "loaded")

        let digest = app.descendants(matching: .any)["today.daily-digest"]
        XCTAssertTrue(digest.waitForExistence(timeout: 5))
        digest.tap()

        XCTAssertTrue(app.descendants(matching: .any)["daily-digest.screen"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["What changed for you"].exists)
    }

    func testSmartAccountCanBeFollowedFromDetail() {
        let app = launch(scenario: "loaded")

        XCTAssertEqual(app.tabBars.buttons.element(boundBy: 1).label, "Smart")
        app.tabBars.buttons["Smart"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["smart.screen"].waitForExistence(timeout: 5))

        let account = app.descendants(matching: .any)["smart.account.row.first"]
        XCTAssertTrue(account.waitForExistence(timeout: 3))
        account.tap()

        let follow = app.buttons["smart.account.follow"]
        XCTAssertTrue(follow.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["View + price evidence"].exists)
        keepScreenshot(app, named: "Smart Account overview")
        follow.tap()
        XCTAssertTrue(app.buttons["Following"].waitForExistence(timeout: 2))

        app.buttons["Evidence"].tap()
        XCTAssertTrue(app.staticTexts["Auditable Call record"].waitForExistence(timeout: 2))
        keepScreenshot(app, named: "Smart Account evidence")

        let evidence = app.descendants(matching: .any)["smart.account.evidence.row.first"]
        XCTAssertTrue(evidence.waitForExistence(timeout: 2))
        evidence.tap()
        XCTAssertTrue(app.descendants(matching: .any)["smart.account.evidence.detail"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Structured Call"].exists)
        XCTAssertTrue(app.staticTexts["Source evidence"].exists)
        keepScreenshot(app, named: "Smart Account evidence detail")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["Method"].tap()
        XCTAssertTrue(app.staticTexts["How to read this Score"].waitForExistence(timeout: 2))
    }

    func testSmartMoneyOpensAuditableWalletAnalytics() {
        let app = launch(scenario: "loaded")

        app.tabBars.buttons["Smart"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["smart.screen"].waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Smart Money")).firstMatch.tap()

        let wallet = app.descendants(matching: .any)["smart.money.row.first"]
        XCTAssertTrue(wallet.waitForExistence(timeout: 3))
        keepScreenshot(app, named: "Smart Money cohort")
        wallet.tap()

        XCTAssertTrue(app.staticTexts["Current read"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Performance & risk"].exists)
        XCTAssertTrue(app.buttons["Open wallet evidence"].exists)
        keepScreenshot(app, named: "Smart Money overview")

        app.buttons["Positions"].tap()
        XCTAssertTrue(app.staticTexts["Current positions"].waitForExistence(timeout: 2))
        keepScreenshot(app, named: "Smart Money positions")

        app.buttons["Activity"].tap()
        XCTAssertTrue(app.staticTexts["Recent trades"].waitForExistence(timeout: 2))
    }

    func testSimplifiedChineseCoversCoreNavigationAndSmartDetails() {
        let app = launch(scenario: "loaded", language: "zh-Hans")

        XCTAssertTrue(app.staticTexts["今日"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.tabBars.buttons.element(boundBy: 1).label, "智能")
        app.tabBars.buttons["智能"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["smart.screen"].waitForExistence(timeout: 5))
        let account = app.descendants(matching: .any)["smart.account.row.first"]
        XCTAssertTrue(account.waitForExistence(timeout: 3))
        account.tap()

        XCTAssertTrue(app.staticTexts["最新公开观点"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["证据"].exists)
        XCTAssertTrue(app.buttons["方法"].exists)
        keepScreenshot(app, named: "Smart Account zh-Hans")

        app.navigationBars["聪明账户"].buttons.firstMatch.tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "聪明资金")).firstMatch.tap()
        let wallet = app.descendants(matching: .any)["smart.money.row.first"]
        XCTAssertTrue(wallet.waitForExistence(timeout: 3))
        wallet.tap()

        XCTAssertTrue(app.staticTexts["当前判断"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["持仓"].exists)
        XCTAssertTrue(app.buttons["动态"].exists)
        keepScreenshot(app, named: "Smart Money zh-Hans")
    }

    func testSimplifiedChineseCoversTodayPortfolioAndResearch() {
        let app = launch(scenario: "loaded", language: "zh-Hans")

        XCTAssertTrue(app.descendants(matching: .any)["today.screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["今日"].exists)
        XCTAssertTrue(app.staticTexts["组合状态"].exists)
        XCTAssertTrue(app.staticTexts["需关注"].exists)
        XCTAssertTrue(app.staticTexts["最需要关注"].exists)
        keepScreenshot(app, named: "Today zh-Hans")

        let signal = app.staticTexts["聪明账户发表看多观点，此前链上资金已开始增持"]
        XCTAssertTrue(signal.waitForExistence(timeout: 3))
        signal.tap()
        XCTAssertTrue(app.descendants(matching: .any)["event-detail.screen"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["证据关系"].exists)
        XCTAssertTrue(app.staticTexts["聪明账户"].exists)
        XCTAssertTrue(app.staticTexts["聪明资金"].exists)
        keepScreenshot(app, named: "Event Detail zh-Hans")
        app.navigationBars["HOOD"].buttons.firstMatch.tap()

        app.tabBars.buttons["持仓"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["portfolio.screen"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["总收益"].exists)
        XCTAssertTrue(app.staticTexts["观察列表"].exists)
        keepScreenshot(app, named: "Portfolio zh-Hans")

        app.tabBars.buttons["研究"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["research.screen"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.navigationBars["智能情报"].exists)
        XCTAssertTrue(app.staticTexts["一项新的有效半导体观点获得高分公开账户的独立确认；AVGO 仍不在当前持仓中。"].exists)
        keepScreenshot(app, named: "Research zh-Hans")
    }

    func testTodaySignalFiltersCanBeCombinedWithUnreadState() {
        let app = launch(scenario: "loaded")

        let evidence = app.buttons["today.filter.evidence"]
        XCTAssertTrue(evidence.waitForExistence(timeout: 5))
        evidence.tap()

        let relationships = app.buttons["today.filter.relationships"]
        XCTAssertTrue(relationships.waitForExistence(timeout: 3))
        relationships.tap()
        XCTAssertTrue(app.staticTexts["2 matching · 4 new"].exists)

        let unread = app.buttons["today.filter.unread"]
        XCTAssertTrue(unread.isHittable)
        unread.tap()
        XCTAssertTrue(unread.isSelected)
        XCTAssertTrue(app.staticTexts["2 matching · 4 new"].exists)
    }

    func testFirstUseCanWatchTickerAndOpenPersonalFeed() {
        let app = launch(scenario: "first-use")

        XCTAssertTrue(app.descendants(matching: .any)["portfolio-setup.screen"].waitForExistence(timeout: 5))
        let watchAVGO = app.buttons["portfolio-setup.watch.AVGO"]
        XCTAssertTrue(watchAVGO.waitForExistence(timeout: 3))
        XCTAssertTrue(watchAVGO.isHittable)
        watchAVGO.tap()

        let continueButton = app.buttons["portfolio-setup.continue"]
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: continueButton)
        waitForExpectations(timeout: 2)
        continueButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["today.screen"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["For your watchlist"].exists)
    }

    func testResearchOpensTickerIntelligenceWithBothEvidenceSystems() {
        let app = launch(scenario: "loaded")

        app.tabBars.buttons["Research"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["research.screen"].waitForExistence(timeout: 5))

        let nvda = app.descendants(matching: .any)["research.ticker.NVDA"]
        XCTAssertTrue(nvda.waitForExistence(timeout: 3))
        nvda.tap()

        XCTAssertTrue(app.descendants(matching: .any)["ticker-intelligence.NVDA"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Current relationship"].exists)
        XCTAssertTrue(app.staticTexts["Smart Account"].exists)
        XCTAssertTrue(app.staticTexts["Smart Money"].exists)
    }

    func testPortfolioEntryOpensIntelligenceAndKeepsNativeEditorAvailable() {
        let app = launch(scenario: "loaded")

        app.tabBars.buttons["Portfolio"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["portfolio.screen"].waitForExistence(timeout: 5))

        let hood = app.buttons["portfolio.entry.HOOD"]
        XCTAssertTrue(hood.waitForExistence(timeout: 3))
        hood.tap()

        XCTAssertTrue(app.descendants(matching: .any)["ticker-intelligence.HOOD"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Current relationship"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let actions = app.buttons["portfolio.entry-actions.HOOD"]
        XCTAssertTrue(actions.waitForExistence(timeout: 3))
        actions.tap()
        let edit = app.buttons["Edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 2))
        edit.tap()

        XCTAssertTrue(app.descendants(matching: .any)["position-editor.screen"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.navigationBars["Edit HOOD"].exists)
        XCTAssertTrue(app.buttons["Save"].exists)
    }

    func testAlertSettingsExposeScheduleAndPerTickerControls() {
        let app = launch(scenario: "loaded")

        let openAlerts = app.buttons["Open alert settings"]
        XCTAssertTrue(openAlerts.waitForExistence(timeout: 5))
        openAlerts.tap()

        XCTAssertTrue(app.descendants(matching: .any)["alerts.screen"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Delivery time"].exists)
        XCTAssertTrue(app.staticTexts["Quiet hours"].exists)

        let nvdaAlerts = app.switches["alerts.ticker.NVDA"]
        XCTAssertTrue(nvdaAlerts.waitForExistence(timeout: 2))
        for _ in 0..<3 where !nvdaAlerts.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(nvdaAlerts.isHittable)
        XCTAssertEqual(nvdaAlerts.value as? String, "1")
        nvdaAlerts.tap()
        XCTAssertEqual(nvdaAlerts.value as? String, "0")
    }

    func testOpportunityCanBeAddedToWatchlistFromEvidenceDetail() {
        let app = launch(scenario: "loaded")

        let radar = app.descendants(matching: .any)["today.opportunity-radar"]
        for _ in 0..<8 where !radar.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(radar.waitForExistence(timeout: 3))
        XCTAssertTrue(radar.isHittable)
        radar.tap()

        XCTAssertTrue(app.descendants(matching: .any)["opportunity-radar.screen"].waitForExistence(timeout: 3))
        let avgo = app.descendants(matching: .any)["opportunity-radar.signal.AVGO"]
        XCTAssertTrue(avgo.waitForExistence(timeout: 3))
        avgo.tap()

        let watch = app.buttons["event.watch.AVGO"]
        XCTAssertTrue(watch.waitForExistence(timeout: 3))
        watch.tap()
        XCTAssertTrue(app.staticTexts["Your watchlist"].waitForExistence(timeout: 2))
    }

    func testLocalDataResetReturnsToPortfolioSetup() {
        let app = launch(scenario: "loaded")

        app.tabBars.buttons["Portfolio"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["portfolio.screen"].waitForExistence(timeout: 5))
        app.buttons["Open settings"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["settings.screen"].waitForExistence(timeout: 3))
        app.descendants(matching: .any)["settings.reset-local-data"].tap()
        app.buttons["Reset local app data"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["portfolio-setup.screen"].waitForExistence(timeout: 3))
    }

    func testSettingsExposeDemoMethodologyAndRiskLimits() {
        let app = launch(scenario: "loaded")

        app.tabBars.buttons["Portfolio"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["portfolio.screen"].waitForExistence(timeout: 5))
        app.buttons["Open settings"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["settings.screen"].waitForExistence(timeout: 3))
        app.buttons["settings.data-methodology"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["methodology.screen"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["This build uses demonstration evidence and events."].exists)
        XCTAssertTrue(app.staticTexts["Smart Account"].exists)
        XCTAssertTrue(app.staticTexts["Smart Money"].exists)

        app.navigationBars["Data & methodology"].buttons.firstMatch.tap()
        app.buttons["settings.risk-disclosure"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["risk-disclosure.screen"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Score limitations"].exists)
        XCTAssertTrue(app.staticTexts["Market risk"].exists)
    }

    func testLanguageCanSwitchImmediatelyInsideSettings() {
        let app = launch(scenario: "loaded")

        app.tabBars.buttons["Portfolio"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["portfolio.screen"].waitForExistence(timeout: 5))
        app.buttons["Open settings"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["settings.screen"].waitForExistence(timeout: 3))
        let chinese = app.buttons["settings.language.zh-Hans"]
        XCTAssertTrue(chinese.waitForExistence(timeout: 2))
        chinese.tap()

        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["完成"].exists)
        XCTAssertTrue(chinese.isSelected)
        keepScreenshot(app, named: "Language settings zh-Hans")

        app.buttons["完成"].tap()
        XCTAssertTrue(app.navigationBars["持仓"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.tabBars.buttons["持仓"].exists)
        app.buttons["portfolio.settings"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings.screen"].waitForExistence(timeout: 3))

        let english = app.buttons["settings.language.en"]
        english.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Done"].exists)
        XCTAssertTrue(english.isSelected)
        keepScreenshot(app, named: "Language settings en")
    }

    private func keepScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launch(scenario: String, language: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        let resolvedLanguage = language ?? "en"
        let resolvedLocale = language == nil ? "en_US" : "zh_CN"
        app.launchArguments = [
            "--ui-reset-state",
            "--ui-scenario=\(scenario)",
            "-AppleLanguages", "(\(resolvedLanguage))",
            "-AppleLocale", resolvedLocale
        ]
        app.launch()
        return app
    }
}
