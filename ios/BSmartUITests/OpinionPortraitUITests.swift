import XCTest

final class OpinionPortraitUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testCompactPortraitPullCollapseAndTradeDockInDarkMode() {
        let app = openOpinion()
        let cover = app.descendants(matching: .any)["opinion.portrait"].firstMatch
        let author = app.staticTexts["opinion.author-name"]
        let ticker = app.staticTexts["opinion.ticker"]
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        XCTAssertTrue(author.isHittable, app.debugDescription)
        XCTAssertTrue(ticker.isHittable)
        let direction = app.staticTexts["opinion.direction"]
        XCTAssertTrue(direction.isHittable)
        XCTAssertEqual(ticker.frame.midY, direction.frame.midY, accuracy: 8)
        assertRankBelowAvatar(in: app, cover: cover)
        XCTAssertGreaterThanOrEqual(author.frame.minY, cover.frame.maxY)
        XCTAssertGreaterThan(ticker.frame.minY, author.frame.maxY)
        XCTAssertEqual(cover.frame.width, app.frame.width, accuracy: 2)
        XCTAssertEqual(cover.frame.height, 205, accuracy: 2)
        let avatar = cover.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "subject.account.")).firstMatch
        let logo = cover.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ticker.logo.")).firstMatch
        XCTAssertTrue(avatar.isHittable)
        XCTAssertTrue(logo.isHittable)
        XCTAssertLessThan(logo.frame.width, avatar.frame.width)
        XCTAssertLessThan(logo.frame.minX, avatar.frame.maxX)
        XCTAssertGreaterThan(logo.frame.minY, avatar.frame.minY)
        for mark in [avatar, logo] {
            XCTAssertGreaterThanOrEqual(mark.frame.minX, cover.frame.minX)
            XCTAssertLessThanOrEqual(mark.frame.maxX, cover.frame.maxX)
            XCTAssertLessThanOrEqual(mark.frame.maxY, cover.frame.maxY)
        }
        let height = cover.frame.height
        let start = cover.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 150)))
        XCTAssertEqual(cover.frame.height, height, accuracy: 2)
        XCTAssertTrue(author.isHittable)
        let symbol = ticker.label
        let dock = app.descendants(matching: .any)["trade.dock.\(symbol.lowercased())"]
        XCTAssertTrue(dock.isHittable)
        XCTAssertFalse(app.descendants(matching: .any)["app.tabbar"].isHittable)
        let traders = app.staticTexts["opinion.traders.count"]
        XCTAssertTrue(traders.waitForExistence(timeout: 5))
        let summary = app.descendants(matching: .any)["opinion.reader.summary"].firstMatch
        XCTAssertTrue(summary.exists)
        XCTAssertLessThanOrEqual(traders.frame.maxY, summary.frame.minY)
        for _ in 0..<4 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.75))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.25)))
        }
        XCTAssertTrue(app.navigationBars.staticTexts[symbol].isHittable)
        XCTAssertTrue(dock.isHittable)
        app.buttons["detail.back"].tap()
        XCTAssertTrue(app.textFields["search.input"].waitForExistence(timeout: 5))
    }

    func testLightLargeTextKeepsNamesAndAuthorDestinationAccessible() {
        let app = openOpinion(light: true)
        let cover = app.descendants(matching: .any)["opinion.portrait"].firstMatch
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        assertRankBelowAvatar(in: app, cover: cover)
        XCTAssertEqual(cover.frame.height, 205, accuracy: 2)
        for id in ["opinion.author-name", "opinion.ticker", "opinion.published-at"] {
            let label = app.staticTexts[id]
            XCTAssertTrue(label.isHittable, app.debugDescription)
            XCTAssertGreaterThanOrEqual(label.frame.minX, cover.frame.minX)
            XCTAssertLessThanOrEqual(label.frame.maxX, cover.frame.maxX)
            XCTAssertGreaterThanOrEqual(label.frame.minY, cover.frame.maxY)
        }
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "subject.account.")).firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["smart.account.portrait"].waitForExistence(timeout: 5))
        let back = app.buttons.matching(identifier: "detail.back").allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(back)
        back?.tap()
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["app.tabbar"].isHittable)
        let symbol = app.staticTexts["opinion.ticker"].label
        cover.buttons["ticker.logo.\(symbol)"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["ticker-intelligence.\(symbol)"].waitForExistence(timeout: 5))
    }

    private func assertRankBelowAvatar(in app: XCUIApplication, cover: XCUIElement) {
        let rank = app.staticTexts["opinion.author-rank"]
        XCTAssertTrue(rank.isHittable)
        XCTAssertEqual(app.staticTexts.matching(identifier: "opinion.author-rank").count, 1)
        let avatar = cover.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "subject.account.")).firstMatch
        XCTAssertEqual(rank.frame.midX, avatar.frame.midX, accuracy: 3)
        XCTAssertGreaterThan(rank.frame.minY, avatar.frame.midY)
        XCTAssertLessThanOrEqual(rank.frame.maxY, cover.frame.maxY)
        XCTAssertFalse(cover.staticTexts["opinion.author-name"].exists)
        XCTAssertFalse(cover.staticTexts["opinion.ticker"].exists)
    }

    private func openOpinion(light: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reset-state", "--ui-scenario=loaded", "--ui-trading-fixture", "--ui-opinion-traders-fixture", "--ui-search-fixture",
            "--ui-appearance", light ? "light" : "dark", "-AppleLanguages", light ? "(zh-Hans)" : "(en)",
            "-AppleLocale", light ? "zh_CN" : "en_US"]
        if light { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"] }
        app.launch()
        let search = app.buttons["app.tab.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        let input = app.textFields["search.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap(); input.typeText("NBIS")
        app.buttons["search.filter.opinions"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "search.result.opinion:")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.tap()
        return app
    }
}
