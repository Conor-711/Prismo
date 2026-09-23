import XCTest

final class TradingFlowUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testMarketHasChartFirstAndPinnedDirectionalActions() {
        let app = openMarket()
        let chart = app.descendants(matching: .any)["hyperliquid.chart"]
        XCTAssertTrue(chart.waitForExistence(timeout: 8))
        let identity = app.buttons["trade.market-picker"]
        XCTAssertTrue(identity.isHittable)
        XCTAssertEqual(app.buttons.matching(identifier: "trade.market-picker").count, 1)
        XCTAssertLessThan(identity.frame.maxY, chart.frame.minY)
        let short = app.buttons["trade.open.nvda.short"]
        let long = app.buttons["trade.open.nvda"]
        XCTAssertTrue(short.isHittable)
        XCTAssertTrue(long.isHittable)
        XCTAssertLessThan(short.frame.midX, long.frame.midX)
        XCTAssertFalse(app.staticTexts["ORDER TICKET"].exists)
        XCTAssertFalse(app.staticTexts["TRADING ACCOUNT"].exists)
        XCTAssertTrue(app.buttons["trade.range.1D"].isSelected)
        app.buttons["trade.range.1W"].tap()
        XCTAssertTrue(app.buttons["trade.range.1W"].isSelected)
    }

    func testTradeSheetShowsStableLoadingLayoutBeforeMarketArrives() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reset-state", "--ui-scenario=loaded", "--ui-trading-fixture",
                               "--ui-trading-delayed-market", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let portfolio = app.descendants(matching: .any)["app.tab.portfolio"]
        XCTAssertTrue(portfolio.waitForExistence(timeout: 8))
        portfolio.tap()
        app.buttons["portfolio.tab.allTickers"].tap()
        let search = app.textFields["portfolio.ticker-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 6))
        search.tap()
        search.typeText("NVDA")
        let ticker = app.descendants(matching: .any)["portfolio.ticker.NVDA"]
        XCTAssertTrue(ticker.waitForExistence(timeout: 6))
        ticker.tap()
        let open = app.buttons["trade.open.nvda"]
        XCTAssertTrue(open.waitForExistence(timeout: 8))
        open.tap()
        let loading = app.descendants(matching: .any)["trade.market.loading"]
        XCTAssertTrue(loading.waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["trade.order.loading"].exists)
        XCTAssertTrue(app.buttons["trade.close"].isHittable)
        XCTAssertFalse(app.descendants(matching: .any)["trading-order.submit"].exists)
        XCTAssertTrue(app.buttons["trade.live.wallet"].waitForExistence(timeout: 10))
        XCTAssertTrue(loading.waitForNonExistence(timeout: 4))
        app.buttons["trade.close"].tap()
    }

    func testLiveOrderEntryAndReturnPreserveMarketRange() {
        let app = openMarket()
        XCTAssertTrue(app.buttons["trade.range.1W"].waitForExistence(timeout: 8))
        app.buttons["trade.range.1W"].tap()
        let open = app.buttons["trade.open.nvda"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: open)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        open.tap()
        XCTAssertTrue(app.descendants(matching: .any)["trade.live.screen"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["app.tab.portfolio"].isHittable)
        XCTAssertFalse(app.buttons["trade.order.done"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["trading-order.submit"].exists)
        app.buttons["trade.close"].tap()
        XCTAssertTrue(app.buttons["trade.close"].waitForNonExistence(timeout: 4))
        XCTAssertTrue(app.buttons["trade.range.1W"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["trade.range.1W"].isSelected)
        XCTAssertTrue(app.buttons["trade.open.nvda"].isHittable)
    }

    func testShortEntryCannotFabricateAnExecutionBeforeWalletSetup() {
        let app = openMarket(language: "zh-Hans")
        XCTAssertTrue(app.buttons["trade.open.nvda.short"].waitForExistence(timeout: 8))
        app.buttons["trade.open.nvda.short"].tap()
        XCTAssertTrue(app.buttons["trade.live.wallet"].waitForExistence(timeout: 8))
        let done = app.buttons["trade.order.done"]
        XCTAssertFalse(done.exists)
        app.buttons["trade.close"].tap()
        XCTAssertTrue(app.buttons["trade.close"].waitForNonExistence(timeout: 4))
        XCTAssertTrue(app.buttons["trade.open.nvda.short"].isHittable)
        app.buttons["trade.open.nvda.short"].tap()
        XCTAssertTrue(app.buttons["trade.live.wallet"].waitForExistence(timeout: 8))
        XCTAssertFalse(done.exists)
        app.buttons["trade.close"].tap()
    }

    func testShortEntryInChineseHasNoMockBalanceOrMaximum() {
        let app = openMarket(language: "zh-Hans")
        XCTAssertTrue(app.buttons["trade.open.nvda.short"].waitForExistence(timeout: 8))
        app.buttons["trade.open.nvda.short"].tap()
        XCTAssertTrue(app.buttons["trade.live.wallet"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["trade.amount.max"].exists)
        XCTAssertFalse(app.staticTexts["trade.amount"].exists)
        app.buttons["trade.close"].tap()
    }

    func testOrderWalletEntryOpensDedicatedWalletThenGoogleLogin() {
        let app = openMarket()
        app.buttons["trade.open.nvda"].tap()
        let wallet = app.buttons["trade.live.wallet"]
        XCTAssertTrue(wallet.waitForExistence(timeout: 8))
        wallet.tap()
        let signin = app.buttons["wallet.signin"]
        XCTAssertTrue(signin.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["wallet.transfer"].exists)
        signin.tap()
        XCTAssertTrue(app.descendants(matching: .any)["account.signin.google"].waitForExistence(timeout: 8))
    }

    func testCatalogCanOpenTickerWithoutIntelligenceSnapshot() {
        let app = openMarket()
        app.buttons["detail.back"].tap()
        app.buttons["portfolio.tab.allTickers"].tap()
        let search = app.textFields["portfolio.ticker-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        search.typeText("MSTR")
        let row = app.descendants(matching: .any)["portfolio.ticker.MSTR"]
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["ticker-intelligence.MSTR"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["hyperliquid.chart"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["trade.open.mstr"].isHittable)
        XCTAssertTrue(app.switches["ticker.chart.opinions-toggle"].exists)
        app.swipeUp()
        XCTAssertTrue(app.descendants(matching: .any)["ticker.holdings.MSTR"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["ticker-intelligence.smart-activity"].exists)
        for _ in 0..<4 {
            if app.descendants(matching: .any)["ticker.about.MSTR"].isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.descendants(matching: .any)["ticker.about.MSTR"].isHittable)
        XCTAssertTrue(app.staticTexts["Strategy"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["ticker.about.NVDA"].exists)
        app.buttons["ticker.section.activity"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["ticker-intelligence.smart-activity"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["ticker.about.MSTR"].exists)
    }

    func testTickerFollowIsDirectAndSurvivesReopening() {
        let app = openMarket()
        XCTAssertTrue(app.buttons["ticker.follow"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["ticker.follow"].isEnabled)
        app.buttons["detail.back"].tap()
        app.buttons["portfolio.tab.allTickers"].tap()
        let search = app.textFields["portfolio.ticker-search"]
        search.tap()
        search.typeText("NBIS")
        let row = app.descendants(matching: .any)["portfolio.ticker.NBIS"]
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.tap()
        let follow = app.buttons["ticker.follow"]
        XCTAssertTrue(follow.waitForExistence(timeout: 8))
        XCTAssertEqual(follow.label, "Follow ticker")
        follow.tap()
        XCTAssertEqual(follow.label, "Unfollow ticker")
        app.buttons["detail.back"].tap()
        XCTAssertTrue(follow.waitForNonExistence(timeout: 5))
        let reopenedRow = app.buttons["portfolio.ticker.NBIS"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: reopenedRow)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed, app.debugDescription)
        reopenedRow.tap()
        XCTAssertTrue(follow.waitForExistence(timeout: 8))
        XCTAssertEqual(follow.label, "Unfollow ticker")
        follow.tap()
        XCTAssertEqual(follow.label, "Follow ticker")
    }

    func testTickerChartOpinionToggleAndCompleteWindowList() {
        let app = openMarket()
        XCTAssertTrue(app.buttons["trade.range.1M"].waitForExistence(timeout: 8))
        app.buttons["trade.range.1M"].tap()
        let toggle = app.switches["ticker.chart.opinions-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        let all = app.buttons["ticker.chart.all-activity"]
        XCTAssertTrue(all.isHittable)
        all.tap()
        XCTAssertTrue(app.descendants(matching: .any)["ticker-intelligence.smart-activity"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["app.tab.portfolio"].isHittable)
        app.buttons["detail.back"].tap()
        XCTAssertTrue(app.switches["ticker.chart.opinions-toggle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["ticker.chart.opinions-toggle"].value as? String, "1")
    }

    func testOpinionBubbleOpensEvidenceRatherThanAuthorProfile() {
        let app = openMarket()
        XCTAssertTrue(app.buttons["trade.range.1M"].waitForExistence(timeout: 8))
        app.buttons["trade.range.1M"].tap()
        app.switches["ticker.chart.opinions-toggle"].tap()
        let bubble = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@",
            "ticker.chart.opinion.account-")).firstMatch
        XCTAssertTrue(bubble.waitForExistence(timeout: 8))
        bubble.tap()
        XCTAssertTrue(app.descendants(matching: .any)["smart.account.evidence.detail"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["app.tab.portfolio"].isHittable)
        XCTAssertFalse(app.staticTexts["Structured Call"].exists)
        XCTAssertFalse(app.staticTexts["Audit trail"].exists)
        let subject = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "subject.account.")).firstMatch
        XCTAssertTrue(subject.isHittable)
        subject.tap()
        XCTAssertTrue(app.buttons["smart.account.follow"].waitForExistence(timeout: 5))
        app.navigationBars["Smart Account"].buttons["detail.back"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["smart.account.evidence.detail"].waitForExistence(timeout: 5))
    }

    func testPortfolioMarketRowUsesDollarPriceAndVolumeInChinese() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reset-state", "--ui-scenario=loaded", "--ui-trading-fixture",
                               "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let portfolio = app.buttons["app.tab.portfolio"]
        XCTAssertTrue(portfolio.waitForExistence(timeout: 8))
        portfolio.tap()
        app.buttons["portfolio.tab.allTickers"].tap()
        let search = app.textFields["portfolio.ticker-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("NVDA")
        let price = app.staticTexts["portfolio.price.NVDA"]
        XCTAssertTrue(price.waitForExistence(timeout: 5))
        XCTAssertTrue(price.label.hasPrefix("$"), price.label)
        XCTAssertFalse(price.label.contains("US"), price.label)
        let volume = app.staticTexts["portfolio.volume.NVDA"]
        XCTAssertTrue(volume.label.contains("交易量"), volume.label)
        XCTAssertFalse(volume.label.contains("24小时"), volume.label)
        XCTAssertTrue(volume.label.contains("$"), volume.label)
        XCTAssertFalse(volume.label.contains("XYZ"))
        XCTAssertFalse(volume.label.contains("Hyperliquid"))
        XCTAssertLessThan(price.frame.height, 26)
        XCTAssertLessThan(volume.frame.midX, price.frame.midX)
        XCTAssertGreaterThan(volume.frame.midY, price.frame.midY)
    }

    func testPortfolioSeparatesExternalHoldingsFromAppAccount() {
        let app = openMarket()
        app.buttons["detail.back"].tap()
        let accountSwitch = app.buttons["portfolio.account.switch"]
        XCTAssertTrue(accountSwitch.waitForExistence(timeout: 5))
        accountSwitch.tap()
        XCTAssertEqual(accountSwitch.value as? String, "External account")
        XCTAssertTrue(app.staticTexts["portfolio.cost.NVDA"].exists)
        XCTAssertTrue(app.staticTexts["portfolio.value.NVDA"].exists)
        XCTAssertTrue(app.staticTexts["portfolio.pnl.NVDA"].exists)
        XCTAssertFalse(app.staticTexts["portfolio.volume.NVDA"].exists)
        accountSwitch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["portfolio.app.live-balances"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["portfolio.app.cash"].exists)
        XCTAssertFalse(app.staticTexts["portfolio.app.equity"].exists)
        XCTAssertFalse(app.buttons["portfolio.entry.NVDA"].exists)
        accountSwitch.tap()
        XCTAssertTrue(app.buttons["portfolio.entry.NVDA"].waitForExistence(timeout: 5))
    }

    func testTabOrderLiveFeedAndWalletSettingsEntry() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reset-state", "--ui-scenario=loaded", "--ui-trading-fixture",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let home = app.buttons["app.tab.today"]
        let feed = app.buttons["app.tab.feed"]
        let smart = app.buttons["app.tab.smart"]
        let profile = app.buttons["app.tab.portfolio"]
        XCTAssertTrue(profile.waitForExistence(timeout: 10))
        XCTAssertLessThan(home.frame.midX, feed.frame.midX)
        XCTAssertLessThan(feed.frame.midX, smart.frame.midX)
        XCTAssertLessThan(smart.frame.midX, profile.frame.midX)
        feed.tap()
        XCTAssertTrue(app.descendants(matching: .any)["feed.screen"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["feed.demo.toggle"].exists)
        XCTAssertFalse(app.buttons["Feed privacy"].exists)
        profile.tap()
        XCTAssertTrue(app.descendants(matching: .any)["portfolio.app.positions"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["portfolio.app.wallet"].exists)
        app.buttons["portfolio.settings"].tap()
        let wallet = app.buttons["settings.wallet"]
        XCTAssertTrue(wallet.waitForExistence(timeout: 5))
        XCTAssertTrue(wallet.isHittable)
        wallet.tap()
        XCTAssertTrue(app.descendants(matching: .any)["wallet.screen"].waitForExistence(timeout: 5))
    }

    func testTodayLogoOpensTickerInsteadOfParentCard() {
        let app = openMarket()
        app.buttons["detail.back"].tap()
        app.descendants(matching: .any)["app.tab.today"].tap()
        let logos = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "ticker.logo."))
        var logo: XCUIElement?
        for _ in 0..<6 {
            logo = logos.allElementsBoundByIndex.first { $0.isHittable }
            if logo != nil { break }
            app.swipeUp()
        }
        guard let logo else { return XCTFail("No navigable ticker logo in Today") }
        let symbol = String(logo.identifier.dropFirst("ticker.logo.".count))
        logo.tap()
        XCTAssertTrue(app.descendants(matching: .any)["ticker-intelligence.\(symbol)"].waitForExistence(timeout: 8))
        app.buttons["detail.back"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["app.tab.today"].waitForExistence(timeout: 5))
    }

    private func openMarket(language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-reset-state", "--ui-scenario=loaded", "--ui-trading-fixture",
            "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"
        ]
        app.launch()
        let portfolio = app.descendants(matching: .any)["app.tab.portfolio"]
        XCTAssertTrue(portfolio.waitForExistence(timeout: 8))
        portfolio.tap()
        let nvda = app.descendants(matching: .any)["portfolio.entry.NVDA"]
        XCTAssertTrue(nvda.waitForExistence(timeout: 6))
        nvda.tap()
        return app
    }
}
