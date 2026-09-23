import XCTest
import UIKit

final class TodayHomeContentUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testDeviceHomeScrollingWithoutResettingUserData() throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Device-only smoke test with the existing signed-in account; no fixture or reset arguments.")
#else
        let app = XCUIApplication()
        app.launch()
        let home = app.buttons["app.tab.today"]
        guard home.waitForExistence(timeout: 20) else {
            throw XCTSkip("An already signed-in device is required; do not perform login in this test.")
        }
        home.tap()
        let directory = app.buttons["discovery.open-directory"]
        XCTAssertTrue(directory.waitForExistence(timeout: 10))
        for _ in 0..<2 {
            for _ in 0..<5 { app.scrollViews["today.page.portfolio"].swipeUp() }
            selectScene("market", app: app)
            app.scrollViews["today.page.market"].swipeUp()
            selectScene("investors", app: app)
            app.scrollViews["today.page.investors"].swipeUp()
            selectScene("portfolio", app: app)
            for _ in 0..<12 {
                if directory.isHittable { break }
                scrollHomeDown(app)
            }
            XCTAssertTrue(directory.isHittable)
            app.scrollViews["discovery.pool"].swipeLeft()
            XCUIDevice.shared.press(.home)
            app.activate()
            XCTAssertTrue(directory.waitForExistence(timeout: 10))
            XCTAssertEqual(app.state, .runningForeground)
        }
#endif
    }

    func testRepeatedHomeScrollingAndBackgroundReturnRemainResponsive() {
        let app = launch(chinese: true)
        for cycle in 0..<3 {
            let pool = app.scrollViews["discovery.pool"]
            for _ in 0..<8 {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                    .press(forDuration: 0.02, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.22)))
            }
            selectScene("market", app: app)
            app.scrollViews["today.page.market"].swipeUp()
            selectScene("investors", app: app)
            app.scrollViews["today.page.investors"].swipeUp()
            selectScene("portfolio", app: app)
            for _ in 0..<10 {
                if pool.isHittable && app.buttons["discovery.open-directory"].isHittable { break }
                scrollHomeDown(app)
            }
            XCTAssertTrue(pool.isHittable, "The header must return after scrolling, cycle \(cycle)")
            pool.swipeLeft()
            XCTAssertTrue(app.buttons["discovery.profile"].waitForExistence(timeout: 5))
            XCUIDevice.shared.press(.home)
            app.activate()
            XCTAssertTrue(app.buttons["discovery.open-directory"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.state, .runningForeground)
        }
        app.buttons["discovery.open-directory"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["smart.screen"].waitForExistence(timeout: 5))
    }

    func testMarketViewsHeadingTabsAndFirstSectionHaveVerticalSeparation() {
        for chinese in [false, true] {
            let app = launch(chinese: chinese)
            let firstTitle = app.buttons["today.holdings.title"]
            XCTAssertTrue(firstTitle.waitForExistence(timeout: 5))
            let heading = app.staticTexts["today.market-views.heading"]
            let tabs = app.descendants(matching: .any)["today.home-tabs"]
            XCTAssertTrue(heading.exists)
            XCTAssertGreaterThanOrEqual(tabs.frame.minY - heading.frame.maxY, 15.5)
            XCTAssertGreaterThanOrEqual(firstTitle.frame.minY - tabs.frame.maxY, 27.5)
            XCTAssertLessThanOrEqual(firstTitle.frame.minY - tabs.frame.maxY, 36)
            app.terminate()
        }
    }

    func testEnglishTabsStaySingleLineWithSpacingAndScrollToSelection() {
        let app = launch()
        let bar = app.descendants(matching: .any)["today.home-tabs"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        let ids = ["portfolio", "market", "investors"]
        let buttons = ids.map { app.buttons["today.tab.\($0)"] }
        let font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        XCTAssertEqual(buttons[0].frame.minX, bar.frame.minX + 16, accuracy: 2)
        for (index, button) in buttons.enumerated() {
            let width = (button.label as NSString).size(withAttributes: [.font: font]).width
            XCTAssertGreaterThanOrEqual(button.frame.width, width - 1, "Tab labels must keep their full single-line width")
            XCTAssertEqual(button.frame.height, bar.frame.height, accuracy: 1)
            if index > 0 {
                XCTAssertEqual(button.frame.minX - buttons[index - 1].frame.maxX, 28, accuracy: 2)
            }
        }
        bar.swipeLeft()
        XCTAssertTrue(buttons[2].isHittable)
        buttons[2].tap()
        XCTAssertTrue(buttons[2].isSelected)
        XCTAssertGreaterThanOrEqual(buttons[2].frame.minX, bar.frame.minX - 1)
        XCTAssertLessThanOrEqual(buttons[2].frame.maxX, bar.frame.maxX + 1)
        buttons[1].tap()
        XCTAssertTrue(buttons[1].isSelected)
        XCTAssertTrue(buttons[1].isHittable)
        bar.swipeRight()
        buttons[0].tap()
        XCTAssertTrue(buttons[0].isSelected)
        XCTAssertEqual(buttons[0].frame.minX, bar.frame.minX + 16, accuracy: 2)
    }

    func testLastCardsScrollClearOfFloatingNavigation() {
        let app = launch(chinese: true)
        let dock = app.descendants(matching: .any)["app.tabbar"]
        let tabs = ["portfolio", "market", "investors"].map { app.buttons["today.tab.\($0)"] }
        for index in 1..<tabs.count {
            XCTAssertGreaterThanOrEqual(tabs[index].frame.minX - tabs[index - 1].frame.maxX, 19)
        }
        assertBottomClearsDock(app.descendants(matching: .any)["today.tracked-activity"],
                              page: app.scrollViews["today.page.portfolio"], dock: dock)
        selectScene("market", app: app)
        let alpha = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "today.smart-alpha."))
        for _ in 0..<5 { app.scrollViews["today.page.market"].swipeUp() }
        XCTAssertGreaterThan(alpha.count, 0)
        let last = alpha.allElementsBoundByIndex.max { $0.frame.maxY < $1.frame.maxY }!
        assertBottomClearsDock(last, page: app.scrollViews["today.page.market"], dock: dock)
    }

    private func assertBottomClearsDock(_ last: XCUIElement, page: XCUIElement, dock: XCUIElement) {
        var previousY: CGFloat?
        for _ in 0..<10 {
            page.swipeUp()
            guard last.exists else { continue }
            let y = last.frame.maxY
            if let previousY, abs(y - previousY) < 1 { break }
            previousY = y
        }
        XCTAssertTrue(last.exists)
        XCTAssertLessThanOrEqual(last.frame.maxY, dock.frame.minY - 8,
                                 "The final content must fully clear the floating navigation after scrolling to the end.")
    }

    func testFloatingNavigationKeepsHomeContentBehindBottomSafeArea() {
        let app = launch(chinese: true)
        let page = app.scrollViews["today.page.portfolio"]
        XCTAssertTrue(page.exists)
        XCTAssertEqual(page.frame.maxY, app.frame.maxY, accuracy: 1,
                       "The home viewport must continue below the floating navigation, not stop at the safe-area edge.")
        let dock = app.descendants(matching: .any)["app.tabbar"]
        XCTAssertEqual(dock.frame.height, 64, accuracy: 1)
        XCTAssertLessThan(dock.frame.maxY, app.frame.maxY)
        for id in ["today", "feed", "search", "portfolio"] {
            let button = app.buttons["app.tab.\(id)"]
            XCTAssertTrue(button.isHittable)
            XCTAssertEqual(button.frame.height, 52, accuracy: 1)
        }
        selectScene("market", app: app)
        XCTAssertEqual(app.scrollViews["today.page.market"].frame.maxY, app.frame.maxY, accuracy: 1)
        selectScene("investors", app: app)
        XCTAssertEqual(app.scrollViews["today.page.investors"].frame.maxY, app.frame.maxY, accuracy: 1)
        reveal(app.buttons["today.smart-updates.title"], app: app)
    }

    func testThreePortraitsAndClearHierarchyWithOnlyThreeSceneTabs() {
        let app = launch()
        let pool = app.scrollViews["discovery.pool"]
        let people = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "discovery.person."))
        let visible = visiblePeople(people, in: pool)
        XCTAssertEqual(visible.count, 3, visible.map { "\($0.identifier): \($0.frame)" }.joined(separator: "\n"))
        let selected = visible.first { $0.isSelected }
        XCTAssertNotNil(selected)
        XCTAssertEqual(selected!.frame.midX, pool.frame.midX, accuracy: 2)
        for portrait in visible {
            XCTAssertTrue(portrait.isHittable)
            XCTAssertGreaterThanOrEqual(portrait.frame.minX, pool.frame.minX - 1)
            XCTAssertLessThanOrEqual(portrait.frame.maxX, pool.frame.maxX + 1)
        }
        XCTAssertFalse(app.scrollViews["discovery.sectors"].exists)
        assertNoHomeFilters(app)
        let views = app.staticTexts["today.market-views.heading"]
        XCTAssertTrue(views.exists)
        let focus = app.buttons["discovery.profile"]
        XCTAssertGreaterThan(views.frame.minY, focus.frame.maxY + 24)
        XCTAssertEqual(views.frame.minX, app.buttons["discovery.open-directory"].frame.minX, accuracy: 2)
        let original = selected!.identifier
        pool.swipeLeft()
        XCTAssertFalse(app.buttons[original].isSelected)
        XCTAssertEqual(visiblePeople(people, in: pool).count, 3)
        assertNoHomeFilters(app)
        selectScene("market", app: app)
        swipeScene(app, forward: true)
        XCTAssertTrue(app.buttons["today.tab.investors"].isSelected)
        swipeScene(app, forward: false)
        XCTAssertTrue(app.buttons["today.tab.market"].isSelected)
    }

    func testDiscoveryTitleOpensSmartHubAndReturnsToSameSelection() {
        let app = launch()
        let selected = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND selected == true", "discovery.person.")).firstMatch
        let selectedID = selected.identifier
        XCTAssertFalse(app.buttons["app.tab.smart"].exists)
        let today = app.buttons["app.tab.today"]
        let feed = app.buttons["app.tab.feed"]
        let profile = app.buttons["app.tab.portfolio"]
        XCTAssertEqual(profile.frame.midX - feed.frame.midX,
                       2 * (feed.frame.midX - today.frame.midX), accuracy: 3)
        app.buttons["discovery.open-directory"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["smart.screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["smart.account.filters"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["app.tabbar"].isHittable)
        app.descendants(matching: .any)["smart.section.money"].tap()
        XCTAssertTrue(app.buttons["smart.money.filters"].exists)
        app.descendants(matching: .any)["smart.section.accounts"].tap()
        app.buttons["smart.account.filters"].tap()
        XCTAssertTrue(app.navigationBars["Filters"].waitForExistence(timeout: 4))
        app.buttons["Done"].tap()
        app.buttons["smart.account.row.first"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["smart.account.detail"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["app.tabbar"].isHittable)
        app.buttons["detail.back"].tap()
        XCTAssertTrue(app.buttons["smart.account.row.first"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["app.tabbar"].isHittable)
        app.buttons["detail.back"].tap()
        XCTAssertTrue(app.buttons["discovery.open-directory"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[selectedID].isSelected)
        XCTAssertTrue(app.descendants(matching: .any)["app.tabbar"].isHittable)
        XCTAssertTrue(today.isSelected)
        assertNoHomeFilters(app)
    }

    func testHoldingsAndSmartUpdatesFiltersOnlyAppearInCollections() {
        let app = launch()
        let holdings = app.buttons["today.holdings.title"]
        reveal(holdings, app: app)
        assertNoHomeFilters(app)
        holdings.tap()
        let holdingsFilter = app.segmentedControls["holdings.source-filter"]
        XCTAssertTrue(holdingsFilter.waitForExistence(timeout: 5))
        holdingsFilter.buttons["Smart Money"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "holdings.activity.money.")).firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["app.tabbar"].isHittable)
        app.buttons["detail.back"].tap()
        XCTAssertTrue(holdings.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["app.tabbar"].isHittable)
        selectScene("market", app: app)
        reveal(app.buttons["today.consensus.title"], app: app)
        reveal(app.buttons["today.alpha.title"], app: app)
        selectScene("investors", app: app)
        let updates = app.buttons["today.smart-updates.title"]
        reveal(updates, app: app)
        assertNoHomeFilters(app)
        updates.tap()
        let updatesFilter = app.segmentedControls["smart-updates.source-filter"]
        XCTAssertTrue(updatesFilter.waitForExistence(timeout: 5))
        updatesFilter.buttons["Smart Account"].tap()
        XCTAssertTrue(app.textFields["smart-updates.search"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["app.tabbar"].isHittable)
        app.buttons["detail.back"].tap()
        XCTAssertTrue(updates.waitForExistence(timeout: 5))
        XCTAssertTrue(updates.isHittable)
        assertNoHomeFilters(app)
    }

    func testChineseLightLargeTextAndEmptyPortfolioKeepAllSectionsAccessible() {
        let app = launch(scenario: "first-use", chinese: true, largeText: true)
        XCTAssertTrue(app.buttons["discovery.open-directory"].isHittable)
        let entry = app.buttons["discovery.open-directory"]
        XCTAssertGreaterThanOrEqual(entry.frame.minX, 0)
        XCTAssertLessThanOrEqual(entry.frame.maxX, app.frame.maxX)
        let pool = app.scrollViews["discovery.pool"]
        XCTAssertTrue(pool.isHittable)
        reveal(app.buttons["holdings.add"], app: app)
        selectScene("market", app: app)
        reveal(app.buttons["today.consensus.title"], app: app)
        selectScene("investors", app: app)
        reveal(app.buttons["today.smart-updates.title"], app: app)
        assertNoHomeFilters(app)
    }

    private func assertNoHomeFilters(_ app: XCUIApplication) {
        XCTAssertTrue(app.descendants(matching: .any)["today.home-tabs"].exists)
        for section in ["portfolio", "market", "investors"] {
            XCTAssertTrue(app.buttons["today.tab.\(section)"].exists)
        }
        XCTAssertFalse(app.segmentedControls["holdings.source-filter"].exists)
        XCTAssertFalse(app.segmentedControls["smart-updates.source-filter"].exists)
        XCTAssertFalse(app.buttons["discovery.directory.sector"].exists)
    }

    private func scrollHomeDown(_ app: XCUIApplication) {
        // The header overlaps the ScrollView; drag its gutter, not an opinion node.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.025, dy: 0.25))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.025, dy: 0.75)))
    }

    private func visiblePeople(_ people: XCUIElementQuery, in pool: XCUIElement) -> [XCUIElement] {
        // XCTest also exposes preloaded scroll targets outside the clipped viewport.
        let viewport = pool.frame
        return people.allElementsBoundByIndex.filter {
            viewport.intersection($0.frame).width > $0.frame.width / 2
        }
    }

    private func selectScene(_ section: String, app: XCUIApplication) {
        let tab = app.buttons["today.tab.\(section)"]
        // Collapse the shared discovery header so a page swipe cannot hit its portrait rail.
        for _ in 0..<4 {
            if tab.isHittable && tab.frame.minY < 140 { break }
            if tab.isHittable {
                // The dock can overlap the lower half of a partially revealed tab.
                tab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
                    .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)))
            } else {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
                    .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)))
            }
        }
        let bar = app.descendants(matching: .any)["today.home-tabs"]
        for _ in 0..<3 {
            if tab.isHittable && tab.frame.minX >= bar.frame.minX && tab.frame.maxX <= bar.frame.maxX { break }
            if tab.frame.minX < bar.frame.minX { bar.swipeRight() }
            else { bar.swipeLeft() }
        }
        XCTAssertTrue(tab.isHittable, app.debugDescription)
        tab.tap()
        XCTAssertTrue(tab.isSelected)
    }

    private func swipeScene(_ app: XCUIApplication, forward: Bool) {
        let tabs = app.descendants(matching: .any)["today.home-tabs"].frame
        let dock = app.descendants(matching: .any)["app.tabbar"].frame
        let viewport = app.frame
        let y = ((tabs.maxY + dock.minY) / 2 - viewport.minY) / viewport.height
        XCTAssertGreaterThan(dock.minY - tabs.maxY, 44, "Tabs \(tabs), dock \(dock), viewport \(viewport)")
        app.coordinate(withNormalizedOffset: CGVector(dx: forward ? 0.85 : 0.15, dy: y))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: forward ? 0.15 : 0.85, dy: y)))
    }

    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<28 {
            if element.exists && element.isHittable && element.frame.maxY < app.frame.height * 0.82 { return }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30)))
        }
        let tabs = ["portfolio", "market", "investors"].map {
            "\($0): \(app.buttons["today.tab.\($0)"].frame)"
        }.joined(separator: ", ")
        XCTFail("Could not reveal \(element.identifier), frame \(element.frame), screen \(app.frame), \(tabs)")
    }

    private func launch(scenario: String = "loaded", chinese: Bool = false, largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reset-state", "--ui-scenario=\(scenario)", "--ui-trading-fixture",
                               "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)",
                               "-AppleLocale", chinese ? "zh_CN" : "en_US",
                               "--ui-appearance", chinese ? "light" : "dark"]
        if scenario == "first-use" { app.launchArguments += ["-bsmart.portfolio-setup-complete.v1", "YES"] }
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"] }
        app.launch()
        XCTAssertTrue(app.buttons["discovery.open-directory"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.scrollViews["discovery.pool"].waitForExistence(timeout: 5))
        return app
    }
}
