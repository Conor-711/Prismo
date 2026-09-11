import XCTest

final class TodayHomePagerUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testHomeTabsUseLeadingContentWidths() {
        for language in ["zh-Hans", "en"] {
            let app = launch(language: language)
            let investorsHeading = app.staticTexts["discovery.heading"]
            let viewsHeading = app.staticTexts["today.market-views.heading"]
            XCTAssertTrue(investorsHeading.waitForExistence(timeout: 10))
            XCTAssertTrue(viewsHeading.exists)
            XCTAssertEqual(investorsHeading.label, language == "en" ? "Smart investors" : "发现聪明投资者")
            XCTAssertEqual(viewsHeading.label, language == "en" ? "Their market views" : "他们怎么看市场")
            XCTAssertGreaterThan(viewsHeading.frame.minY, investorsHeading.frame.maxY)
            screenshot(app, "Home hierarchy - overview - \(language)")
            revealTabs(app)
            let tabs = ["portfolio", "market", "investors"].map { app.buttons["today.tab.\($0)"] }
            XCTAssertEqual(tabs[0].frame.minX - app.frame.minX, 16, accuracy: 2)
            let gap = tabs[1].frame.minX - tabs[0].frame.maxX
            XCTAssertEqual(gap, 12, accuracy: 2)
            for index in 1..<tabs.count {
                XCTAssertEqual(tabs[index].frame.minX - tabs[index - 1].frame.maxX, gap, accuracy: 2)
            }
            XCTAssertLessThanOrEqual(tabs[2].frame.maxX, app.frame.maxX - 14)
            XCTAssertLessThanOrEqual(viewsHeading.frame.maxY, tabs[0].frame.minY)
            if language == "zh-Hans" {
                XCTAssertGreaterThan(app.frame.maxX - tabs[2].frame.maxX, 40)
            }
            screenshot(app, "Home tabs - leading - \(language)")
            let holdingsTitle = app.buttons["today.holdings.title"]
            for _ in 0..<8 {
                if holdingsTitle.isHittable && holdingsTitle.frame.maxY < app.frame.height * 0.6 { break }
                scrollStep(app, up: true)
            }
            screenshot(app, "Home hierarchy - submodule - \(language)")
            for tab in [tabs[1], tabs[2], tabs[0]] {
                tab.tap()
                XCTAssertTrue(tab.isSelected)
            }
            app.terminate()
        }
    }

    func testCompactHeaderExposesAllThreeTabsWithoutScrolling() {
        assertCompactHeader(launch(), screenshotName: "Compact home - Chinese dark")
    }

    func testCompactHeaderInEnglishLightMode() {
        assertCompactHeader(launch(language: "en", appearance: "light"), screenshotName: "Compact home - English light")
    }

    func testReadingRhythmGroupingFiltersAndAlphaReturn() {
        let app = launch()
        let sources = app.segmentedControls["holdings.source-filter"]
        XCTAssertTrue(app.descendants(matching: .any)["today.screen"].waitForExistence(timeout: 10))
        for _ in 0..<8 {
            if sources.exists && sources.isHittable { break }
            scrollStep(app, up: true)
        }
        XCTAssertTrue(sources.waitForExistence(timeout: 5))
        sources.buttons["Smart Money"].tap()
        let money = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "holdings.activity.money.")).firstMatch
        XCTAssertTrue(money.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["holdings.group.NVDA"].exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "holdings.activity.account.")).firstMatch.exists)
        for _ in 0..<8 {
            if money.isHittable && money.frame.maxY < app.frame.height * 0.8 { break }
            scrollStep(app, up: true)
        }
        screenshot(app, "Reading rhythm - holdings list - money")
        money.tap()
        XCTAssertTrue(app.descendants(matching: .any)["smart-money.movement-detail"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["today.tab.market"].tap()
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "today.viewpoint-package."))
        XCTAssertEqual(cards.count, 2)
        let cardHeight = cards.firstMatch.frame.height
        screenshot(app, "Reading rhythm - equal trending cards")
        let alpha = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "today.smart-alpha.")).firstMatch
        for _ in 0..<8 {
            if alpha.exists && alpha.isHittable && alpha.frame.midY < app.frame.height * 0.75 { break }
            app.swipeUp()
        }
        XCTAssertTrue(alpha.isHittable)
        XCTAssertLessThan(alpha.frame.height, cardHeight)
        screenshot(app, "Reading rhythm - lightweight Alpha rows")
        alpha.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.45)).tap()
        let back = app.buttons["today.smart-alpha.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(app.buttons["today.tab.market"].isSelected)
        XCTAssertTrue(alpha.isHittable)
        app.buttons["today.tab.investors"].tap()
        screenshot(app, "Reading rhythm - author timeline")
    }

    func testReadingRhythmLightModeAndLargeText() {
        let app = launch(language: "en", appearance: "light", largeText: true)
        revealTabs(app)
        let holding = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "holdings.activity.account.")).firstMatch
        for _ in 0..<8 {
            if holding.exists && holding.isHittable && holding.frame.maxY < app.frame.height * 0.8 { break }
            scrollStep(app, up: true)
        }
        XCTAssertTrue(holding.isHittable)
        XCTAssertLessThanOrEqual(holding.frame.maxX, app.frame.maxX - 12)
        XCTAssertGreaterThanOrEqual(holding.frame.minX, app.frame.minX + 12)
        screenshot(app, "Reading rhythm - light holdings - large text")
        app.buttons["today.tab.market"].tap()
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "today.viewpoint-package."))
        XCTAssertEqual(cards.count, 2)
        XCTAssertEqual(cards.firstMatch.frame.height, cards.element(boundBy: 1).frame.height, accuracy: 1)
        screenshot(app, "Reading rhythm - light market - large text")
        app.buttons["today.tab.investors"].tap()
        let investor = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "smart-updates.investor.")).firstMatch
        XCTAssertTrue(investor.waitForExistence(timeout: 5))
        for _ in 0..<3 {
            if investor.frame.minY < app.frame.height * 0.4 { break }
            app.swipeUp()
        }
        screenshot(app, "Reading rhythm - light author timeline - large text")
    }

    private func assertCompactHeader(_ app: XCUIApplication, screenshotName: String) {
        let discovery = app.descendants(matching: .any)["today.discovery"]
        XCTAssertTrue(discovery.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["discovery.heading"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["today.price-chart"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["today.data-updated-at"].exists)
        XCTAssertFalse(app.staticTexts["Smart activity"].exists)
        XCTAssertFalse(app.staticTexts["聪明账户动态"].exists)
        let navigation = app.descendants(matching: .any)["app.tabbar"]
        XCTAssertTrue(navigation.exists)
        for section in ["portfolio", "market", "investors"] {
            let tab = app.buttons["today.tab.\(section)"]
            XCTAssertTrue(tab.isHittable)
            XCTAssertLessThan(tab.frame.maxY, navigation.frame.minY - 8,
                              "Scene tabs must be fully above the floating navigation on first load")
        }
        screenshot(app, screenshotName)
        app.buttons["today.settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].exists || app.navigationBars["设置"].exists)
    }

    func testSharedDiscoveryTabsSwipingAndEvidenceReturn() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["discovery.heading"].waitForExistence(timeout: 10))
        app.buttons["discovery.autoplay"].tap()
        let investor = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "discovery.person.")).element(boundBy: 1)
        investor.tap()
        let selectedID = investor.identifier
        revealTabs(app)
        XCTAssertTrue(app.buttons["today.tab.portfolio"].isSelected)
        app.buttons["today.tab.market"].tap()
        XCTAssertTrue(app.buttons["today.consensus.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["today.tab.market"].isSelected)
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "today.viewpoint-package."))
        XCTAssertEqual(cards.count, 2)
        XCTAssertEqual(cards.element(boundBy: 0).frame.height, cards.element(boundBy: 1).frame.height, accuracy: 1)
        let tabY = app.buttons["today.tab.market"].frame.minY
        app.swipeUp()
        XCTAssertEqual(app.buttons["today.tab.market"].frame.minY, tabY, accuracy: 2)
        screenshot(app, "Home tabs - market - pinned")

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.48))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.48)))
        XCTAssertTrue(app.buttons["today.tab.investors"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["today.tab.investors"].isSelected)
        let title = app.buttons["today.smart-updates.title"]
        XCTAssertTrue(title.isHittable)
        screenshot(app, "Home tabs - Smart updates")
        title.tap()
        XCTAssertTrue(app.descendants(matching: .any)["smart-updates.collection"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["today.tab.investors"].isSelected)
        app.buttons["today.tab.portfolio"].tap()
        XCTAssertTrue(app.buttons["today.tab.portfolio"].isSelected)
        screenshot(app, "Home tabs - holdings and tracking")
        let discoveryHeading = app.staticTexts["discovery.heading"]
        for _ in 0..<8 {
            if discoveryHeading.isHittable { break }
            app.swipeDown()
        }
        XCTAssertTrue(discoveryHeading.isHittable)
        XCTAssertTrue(app.buttons[selectedID].isSelected)
        screenshot(app, "Home tabs - shared discovery preserved")
    }

    func testNoHoldingsStillAllowsMarketAndSmartUpdatesInLightMode() {
        let app = launch(scenario: "first-use", language: "en", appearance: "light")
        revealTabs(app)
        XCTAssertTrue(app.buttons["today.tab.portfolio"].isSelected)
        XCTAssertTrue(app.buttons["holdings.add"].exists)
        app.buttons["today.tab.market"].tap()
        XCTAssertTrue(app.buttons["today.consensus.title"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "today.viewpoint-package.")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["today.tab.investors"].tap()
        XCTAssertTrue(app.buttons["today.smart-updates.title"].waitForExistence(timeout: 3))
        screenshot(app, "Home tabs - no holdings - English light")
    }

    private func revealTabs(_ app: XCUIApplication) {
        let tab = app.buttons["today.tab.portfolio"]
        for _ in 0..<8 {
            if tab.isHittable && tab.frame.minY < 100 { return }
            scrollStep(app, up: true)
        }
        XCTAssertTrue(tab.isHittable)
        XCTAssertLessThan(tab.frame.minY, 100, "The scene tabs must pin after the discovery header scrolls away")
    }

    private func scrollStep(_ app: XCUIApplication, up: Bool) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: up ? 0.7 : 0.45))
            .press(forDuration: 0.05,
                   thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: up ? 0.45 : 0.7)),
                   withVelocity: .slow, thenHoldForDuration: 0.15)
    }

    private func launch(scenario: String = "loaded", language: String = "zh-Hans", appearance: String = "dark",
                        largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reset-state", "--ui-scenario=\(scenario)", "--ui-trading-fixture",
                               "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN",
                               "--ui-appearance", appearance]
        if scenario == "first-use" { app.launchArguments += ["-bsmart.portfolio-setup-complete.v1", "YES"] }
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"] }
        app.launch()
        return app
    }

    private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
