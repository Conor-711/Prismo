import XCTest

final class AppSearchUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testThirdTabOverviewExactTickerAndDetailNavigation() {
        let app = launch()
        let tabs = ["today", "feed", "search", "portfolio"].map { app.buttons["app.tab.\($0)"] }
        for i in 1..<tabs.count { XCTAssertLessThan(tabs[i-1].frame.midX, tabs[i].frame.midX) }
        XCTAssertTrue(element("search.overview.tickers", app).waitForExistence(timeout: 8))
        XCTAssertTrue(element("search.overview.authors", app).exists)
        let input = app.textFields["search.input"]
        input.tap(); input.typeText("BTC")
        let btc = app.buttons["search.result.ticker:BTC"]
        XCTAssertTrue(btc.waitForExistence(timeout: 8))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "search.result.ticker:")).firstMatch.identifier,
                       "search.result.ticker:BTC")
        app.buttons["search.dismiss-keyboard"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        btc.tap()
        XCTAssertTrue(element("ticker-intelligence.BTC", app).waitForExistence(timeout: 8))
        assertSingleBackButton(app)
        XCTAssertFalse(app.buttons["app.tab.search"].isHittable)
        app.buttons["detail.back"].firstMatch.tap()
        XCTAssertTrue(btc.waitForExistence(timeout: 8))
        XCTAssertEqual(input.value as? String, "BTC")
    }

    func testMissingPerpMarketShowsExternalAssetLinks() {
        let app = launch()
        let input = app.textFields["search.input"]
        input.tap(); input.typeText("LULU")
        let result = app.buttons["search.result.ticker:LULU"]
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        app.buttons["search.dismiss-keyboard"].tap()
        result.tap()
        XCTAssertTrue(element("trade.external-venues", app).waitForExistence(timeout: 12))
        XCTAssertTrue(element("trade.external.robinhood", app).exists, app.debugDescription)
        XCTAssertTrue(element("trade.external.etoro", app).exists)
        XCTAssertTrue(element("trade.external.moomoo", app).exists)
        XCTAssertTrue(app.buttons["trade.external.open"].exists)
        XCTAssertFalse(app.buttons["trade.open.lulu"].exists)
        app.buttons["trade.external.open"].tap()
        let compactSheet = app.scrollViews["trade.external.sheet"]
        XCTAssertTrue(compactSheet.waitForExistence(timeout: 5))
        XCTAssertLessThan(compactSheet.frame.height, app.frame.height * 0.65)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "external-trade-lulu"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    func testMarketConnectionFailureDoesNotOfferExternalTrading() {
        let app = launch(marketError: true)
        let input = app.textFields["search.input"]
        input.tap(); input.typeText("LULU")
        let result = app.buttons["search.result.ticker:LULU"]
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        app.buttons["search.dismiss-keyboard"].tap()
        result.tap()
        XCTAssertTrue(app.buttons["trade.market.retry"].waitForExistence(timeout: 12))
        XCTAssertFalse(element("trade.external-venues", app).exists)
        XCTAssertFalse(app.buttons["trade.external.open"].exists)
    }

    func testMissingPerpMarketChineseLargeTextLayout() {
        let app = launch(chinese: true)
        let input = app.textFields["search.input"]
        input.tap(); input.typeText("LULU")
        let result = app.buttons["search.result.ticker:LULU"]
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        app.buttons["search.dismiss-keyboard"].tap()
        result.tap()
        XCTAssertTrue(element("trade.external-venues", app).waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["Hyperliquid 暂无该合约市场"].exists)
        XCTAssertTrue(app.buttons["trade.external.open"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "external-trade-lulu-zh-large"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    func testOpinionAndUserResultsOpenTheirOwnDetails() {
        let app = launch()
        let input = app.textFields["search.input"]
        input.tap(); input.typeText("NVDA")
        XCTAssertTrue(app.buttons["search.result.ticker:NVDA"].waitForExistence(timeout: 8))
        app.buttons["search.filter.opinions"].tap()
        let opinion = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "search.result.opinion:")).firstMatch
        XCTAssertTrue(opinion.waitForExistence(timeout: 8))
        opinion.tap()
        XCTAssertTrue(element("smart.account.evidence.detail", app).waitForExistence(timeout: 8))
        assertSingleBackButton(app)
        app.buttons["detail.back"].firstMatch.tap()
        XCTAssertTrue(input.waitForExistence(timeout: 8))
        app.buttons["search.clear"].tap(); input.typeText("Casey")
        let user = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "search.result.user:")).firstMatch
        XCTAssertTrue(user.waitForExistence(timeout: 8))
        app.buttons["search.dismiss-keyboard"].tap()
        user.tap()
        XCTAssertTrue(element("feed.profile.nickname", app).waitForExistence(timeout: 8))
        assertSingleBackButton(app)
        XCTAssertEqual(element("feed.profile.nickname", app).label, "Casey")
    }

    func testOverviewTilesFillEqualColumnsAndInvestorsHaveRanksAndOneBackButton() {
        let app = launch(light: true)
        let tiles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "search.overview.ticker:"))
        XCTAssertTrue(tiles.firstMatch.waitForExistence(timeout: 8))
        XCTAssertEqual(tiles.count, 6)
        let first = tiles.element(boundBy: 0), second = tiles.element(boundBy: 1)
        XCTAssertEqual(first.frame.width, second.frame.width, accuracy: 1)
        XCTAssertEqual(first.frame.height, second.frame.height, accuracy: 1)
        XCTAssertEqual(first.frame.minY, second.frame.minY, accuracy: 1)
        XCTAssertEqual(first.frame.minX, 20, accuracy: 2)
        XCTAssertEqual(second.frame.maxX, app.frame.maxX - 20, accuracy: 2)
        XCTAssertEqual(second.frame.minX - first.frame.maxX, 10, accuracy: 1)
        for tile in tiles.allElementsBoundByIndex {
            let symbol = String(tile.identifier.dropFirst("search.overview.ticker:".count))
            let title = app.staticTexts["search.tile.symbol.\(symbol)"]
            let price = app.staticTexts["search.tile.price.\(symbol)"]
            XCTAssertTrue(title.exists && price.exists)
            XCTAssertLessThanOrEqual(title.frame.maxX, tile.frame.maxX - 10)
            XCTAssertLessThanOrEqual(price.frame.maxX, tile.frame.maxX - 10)
            XCTAssertLessThanOrEqual(title.frame.maxY, price.frame.minY)
        }
        let author = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "search.overview.author:")).firstMatch
        for _ in 0..<3 where !author.isHittable { app.swipeUp() }
        XCTAssertTrue(author.isHittable)
        XCTAssertTrue(author.label.contains("Top "))
        author.tap()
        XCTAssertTrue(element("smart.account.detail", app).waitForExistence(timeout: 8))
        assertSingleBackButton(app)
        XCTAssertFalse(app.buttons["app.tab.search"].isHittable)
        app.buttons["detail.back"].tap()
        XCTAssertTrue(app.textFields["search.input"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["app.tab.search"].isHittable)
    }

    func testChineseLightLargeTextEmptyStateAndClear() {
        let app = launch(chinese: true)
        let input = app.textFields["search.input"]
        XCTAssertGreaterThanOrEqual(input.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(input.frame.maxX, app.frame.maxX)
        input.tap(); input.typeText("qqnomatch987")
        XCTAssertTrue(element("search.empty", app).waitForExistence(timeout: 8))
        app.buttons["search.clear"].tap()
        app.buttons["search.dismiss-keyboard"].tap()
        XCTAssertTrue(element("search.overview.tickers", app).waitForExistence(timeout: 8))
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "search.overview.ticker:"))
        for row in rows.allElementsBoundByIndex where row.isHittable {
            XCTAssertGreaterThanOrEqual(row.frame.minX, app.frame.minX)
            XCTAssertLessThanOrEqual(row.frame.maxX, app.frame.maxX)
            XCTAssertGreaterThanOrEqual(row.frame.height, 44)
        }
        app.swipeUp()
        XCTAssertTrue(input.isHittable)
        XCTAssertTrue(app.buttons["app.tab.search"].isHittable)
    }

    func testMoneyAndMovementDestinationsHaveOneBackButton() {
        let app = launch()
        let input = app.textFields["search.input"]
        input.tap(); input.typeText("dead NBIS")
        XCTAssertTrue(app.buttons["search.filter.authors"].waitForExistence(timeout: 8))
        app.buttons["search.filter.authors"].tap()
        let money = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "search.result.money:")).firstMatch
        XCTAssertTrue(money.waitForExistence(timeout: 8))
        money.tap()
        XCTAssertTrue(app.buttons["detail.back"].waitForExistence(timeout: 8))
        assertSingleBackButton(app)
        app.buttons["detail.back"].tap()
        XCTAssertTrue(input.waitForExistence(timeout: 8))
        app.buttons["search.filter.opinions"].tap()
        let movement = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "search.result.movement:")).firstMatch
        XCTAssertTrue(movement.waitForExistence(timeout: 8))
        movement.tap()
        XCTAssertTrue(app.buttons["detail.back"].waitForExistence(timeout: 8))
        assertSingleBackButton(app)
        app.buttons["detail.back"].tap()
        XCTAssertTrue(input.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["app.tab.search"].isHittable)
    }

    func testUnavailableMarketDirectoryOffersRetryInsteadOfFalseEmptyResult() {
        let app = launch(marketError: true)
        let input = app.textFields["search.input"]
        input.tap(); input.typeText("BTC")
        XCTAssertTrue(app.buttons["search.markets.retry"].waitForExistence(timeout: 8))
        XCTAssertFalse(element("search.empty", app).exists)
        app.buttons["search.dismiss-keyboard"].tap()
        app.buttons["search.markets.retry"].tap()
        XCTAssertTrue(app.buttons["search.markets.retry"].waitForExistence(timeout: 8))
        app.buttons["search.clear"].tap(); input.typeText("NVDA")
        XCTAssertTrue(app.buttons["search.result.ticker:NVDA"].waitForExistence(timeout: 8))
    }

    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    private func assertSingleBackButton(_ app: XCUIApplication) {
        XCTAssertEqual(app.buttons.matching(identifier: "detail.back").count, 1)
        XCTAssertTrue(app.buttons["detail.back"].isHittable)
        XCTAssertEqual(app.navigationBars.buttons.matching(NSPredicate(format: "identifier == %@", "detail.back")).count, 1)
    }
    private func launch(chinese: Bool = false, marketError: Bool = false, light: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reset-state", "--ui-scenario=loaded", "--ui-trading-fixture", "--ui-search-fixture",
            "--ui-section=search", "--ui-appearance", chinese || light ? "light" : "dark",
            "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)", "-AppleLocale", chinese ? "zh_CN" : "en_US"]
        if chinese { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"] }
        if marketError { app.launchArguments += ["--ui-search-market-error"] }
        app.launch()
        XCTAssertTrue(app.textFields["search.input"].waitForExistence(timeout: 12))
        return app
    }
}
