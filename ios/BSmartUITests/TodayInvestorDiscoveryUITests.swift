import XCTest

final class TodayInvestorDiscoveryUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testFirstScreenAndCohortPaging() {
        let app = launch()
        XCTAssertFalse(app.descendants(matching: .any)["today.portfolio-now"].exists)
        XCTAssertFalse(app.buttons["discovery.mode.views"].exists)
        XCTAssertFalse(app.buttons["discovery.page.next"].exists)
        let featured = app.buttons["discovery.person.x:1940360837547565056"]
        XCTAssertTrue(featured.isSelected)
        XCTAssertTrue(featured.label.contains("@aleabitoreddit"))
        XCTAssertEqual(featured.value as? String, "X · Top 15%")
        let avatars = people(app)
        XCTAssertGreaterThanOrEqual(avatars.count, 5)
        XCTAssertGreaterThanOrEqual(avatars.allElementsBoundByIndex.filter { $0.isHittable && $0.label.contains(", YouTube") }.count, 3)
        XCTAssertGreaterThanOrEqual(avatars.allElementsBoundByIndex.filter { $0.isHittable && $0.label.contains(", Reddit") }.count, 1)
        XCTAssertEqual(featured.frame.midX, app.scrollViews["discovery.pool"].frame.midX, accuracy: 2)
        capture(app, "Discovery - horizontal default")
        let original = selectedPerson(app)
        app.scrollViews["discovery.pool"].swipeLeft()
        XCTAssertNotEqual(selectedPerson(app), original)
        XCTAssertTrue(people(app).allElementsBoundByIndex.contains { $0.isHittable && $0.label.contains(", Reddit") })
        XCTAssertTrue(app.buttons["today.tab.portfolio"].isSelected)
        let forward = selectedPerson(app)
        app.scrollViews["discovery.pool"].swipeRight()
        XCTAssertNotEqual(selectedPerson(app), forward)
        assertTabsAboveDock(app)
        capture(app, "Discovery - people")
    }

    func testSectorPersonSelectionAndProfileReturn() {
        let app = launch()
        let sector = app.buttons["discovery.sector.Semiconductors"]
        let strip = app.scrollViews["discovery.sectors"]
        for _ in 0..<6 { if sector.isHittable { break }; strip.swipeLeft() }
        XCTAssertTrue(sector.isHittable)
        sector.tap()
        let avatar = people(app).element(boundBy: 1)
        avatar.tap()
        let id = avatar.identifier
        XCTAssertTrue(app.buttons[id].isSelected)
        XCTAssertTrue(sector.isSelected)
        capture(app, "Discovery - sector focus")
        app.buttons["discovery.profile"].tap()
        XCTAssertTrue(app.buttons["detail.back"].waitForExistence(timeout: 5))
        app.buttons["detail.back"].tap()
        XCTAssertTrue(app.staticTexts["discovery.heading"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[id].isSelected)
        XCTAssertTrue(sector.isSelected)
    }

    func testProfileBrowseFollowAndHomeSelectionSurviveReturn() {
        let app = launch()
        let selected = app.buttons["discovery.person.x:1940360837547565056"]
        selected.tap()
        let id = selected.identifier
        let profile = app.buttons["discovery.profile"]
        let originalY = profile.frame.minY
        let follow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "discovery.follow.")).firstMatch
        XCTAssertEqual(follow.value as? String, "Not tracking")
        follow.tap()
        XCTAssertEqual(follow.value as? String, "Tracking")
        profile.tap()
        let next = app.buttons["discovery.browser.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        let originalIndex = app.staticTexts["discovery.browser.count"].label
        XCTAssertTrue(app.buttons["smart.account.follow"].label.contains("Tracking"))
        next.tap()
        XCTAssertTrue(app.buttons["discovery.browser.previous"].isEnabled)
        app.buttons["discovery.browser.previous"].tap()
        XCTAssertEqual(app.staticTexts["discovery.browser.count"].label, originalIndex)
        app.buttons["smart.account.follow"].tap()
        capture(app, "Discovery - shared profile")
        app.buttons["detail.back"].tap()
        XCTAssertTrue(profile.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[id].isSelected)
        XCTAssertEqual(profile.frame.minY, originalY, accuracy: 2)
        XCTAssertEqual(follow.value as? String, "Not tracking")
        XCTAssertTrue(app.descendants(matching: .any)["app.tabbar"].isHittable)
    }

    func testSearchScopesProfileNavigationAndHasEmptyState() {
        let app = launch()
        app.buttons["discovery.search"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Etrading")
        let profile = app.buttons["discovery.directory.profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "discovery.directory.profile").count, 1)
        profile.tap()
        XCTAssertTrue(app.buttons["discovery.browser.next"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["discovery.browser.next"].isEnabled)
        XCTAssertFalse(app.buttons["discovery.browser.previous"].isEnabled)
        app.buttons["detail.back"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("zzzz-no-match")
        XCTAssertFalse(app.buttons["discovery.directory.profile"].exists)
        capture(app, "Discovery - empty search")
        if !app.buttons["discovery.directory.close"].exists {
            // Native search temporarily replaces the directory toolbar while editing.
            let endSearch = app.navigationBars.buttons.matching(
                NSPredicate(format: "label IN %@", ["Close", "Cancel"])).firstMatch
            XCTAssertTrue(endSearch.exists)
            endSearch.tap()
        }
        XCTAssertTrue(app.buttons["discovery.directory.close"].waitForExistence(timeout: 5))
        app.buttons["discovery.directory.close"].tap()
        XCTAssertTrue(app.staticTexts["discovery.heading"].waitForExistence(timeout: 5))
    }

    func testNewUserCanDiscoverWithoutPositionsInChinese() {
        let app = launch(scenario: "first-use", language: "zh-Hans")
        XCTAssertGreaterThan(people(app).count, 0)
        XCTAssertTrue(app.buttons["discovery.person.x:1940360837547565056"].isSelected)
        assertTabsAboveDock(app)
        capture(app, "Discovery - first use Chinese")
    }

    func testLightModeLargeTextKeepsDiscoveryAndNavigationAccessible() {
        let app = launch(appearance: "light", largeText: true)
        for avatar in people(app).allElementsBoundByIndex where avatar.isHittable {
            XCTAssertGreaterThanOrEqual(avatar.frame.width, 44)
            XCTAssertGreaterThanOrEqual(avatar.frame.height, 44)
            XCTAssertGreaterThanOrEqual(avatar.frame.minX, 0)
            XCTAssertLessThanOrEqual(avatar.frame.maxX, app.frame.maxX)
        }
        capture(app, "Discovery - light large text")
        XCTAssertTrue(app.buttons["discovery.profile"].isHittable)
        let selected = selectedPerson(app)
        app.scrollViews["discovery.pool"].swipeLeft()
        XCTAssertNotEqual(selectedPerson(app), selected)
        // Large Dynamic Type can put the lower sections below the first viewport.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.64))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.28)))
        assertTabsAboveDock(app)
    }

    func testPoolStaysStillUntilUserSwipes() {
        let app = launch()
        XCTAssertFalse(app.staticTexts["discovery.page-count"].exists)
        XCTAssertFalse(app.buttons["discovery.autoplay"].exists)
        let initial = selectedPerson(app)
        waitForMotion(12)
        XCTAssertEqual(selectedPerson(app), initial)
        app.scrollViews["discovery.pool"].swipeLeft()
        let current = selectedPerson(app)
        XCTAssertNotEqual(current, initial)
        waitForMotion(12)
        XCTAssertEqual(selectedPerson(app), current)
    }

    func testFocusHighlightsRealWorkInsteadOfRawScore() {
        let app = launch(language: "zh-Hans")
        let focus = app.descendants(matching: .any)["discovery.focus.x:1940360837547565056"]
        let highlight = focus.descendants(matching: .any)["discovery.highlight"]
        XCTAssertTrue(highlight.waitForExistence(timeout: 5))
        XCTAssertTrue(highlight.label.contains("AAOI"))
        XCTAssertTrue(highlight.label.contains("65.2%"))
        XCTAssertTrue(highlight.label.contains("股价"))
        XCTAssertTrue(highlight.label.contains("2026/02/27"))
        XCTAssertTrue(highlight.label.contains("53.69"))
        XCTAssertTrue(highlight.label.contains("最早加分看多"))
        XCTAssertTrue(focus.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Score'")).allElementsBoundByIndex.isEmpty)
        XCTAssertFalse(focus.staticTexts["X #33"].exists)
        XCTAssertLessThanOrEqual(focus.frame.height, 96)
        capture(app, "Discovery - representative introduction")
        highlight.tap()
        let published = app.descendants(matching: .any)["discovery.receipt.published"]
        XCTAssertTrue(published.waitForExistence(timeout: 5))
        let date = app.descendants(matching: .any)["discovery.receipt.price-date"]
        XCTAssertTrue(date.label.contains("2026-02-26"))
        capture(app, "Discovery - first opinion receipt")
    }

    func testRepresentativeIntroFitsLargeTypeAndDirectoryHasWorkWithoutOpeningProfiles() {
        let app = launch(appearance: "light", largeText: true)
        let focus = app.descendants(matching: .any)["discovery.focus.x:1940360837547565056"]
        let work = focus.buttons["discovery.highlight"]
        XCTAssertTrue(work.label.contains("65.2%"))
        XCTAssertTrue(work.label.contains("53.69"))
        XCTAssertLessThanOrEqual(work.frame.maxX, focus.frame.maxX)
        XCTAssertGreaterThanOrEqual(work.frame.minX, focus.frame.minX)
        XCTAssertLessThanOrEqual(focus.frame.height, 100)
        capture(app, "Discovery - large type representative")
        app.buttons["discovery.search"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Wey How")
        let directoryWork = app.descendants(matching: .any)["discovery.focus.x:1707559719215489024"]
            .buttons["discovery.highlight"]
        XCTAssertTrue(directoryWork.waitForExistence(timeout: 5))
        XCTAssertTrue(directoryWork.label.contains("MU"))
        XCTAssertTrue(directoryWork.label.contains("2025/12/05"))
        XCTAssertTrue(directoryWork.label.contains("237.22"))
        capture(app, "Discovery - Wey How representative")
    }

    private func waitForMotion(_ seconds: Double) {
        let elapsed = expectation(description: "Allow the native animation clock to advance")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { elapsed.fulfill() }
        wait(for: [elapsed], timeout: seconds + 2)
    }

    private func people(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "discovery.person."))
    }

    private func selectedPerson(_ app: XCUIApplication) -> String {
        let selected = people(app).allElementsBoundByIndex.first { $0.isSelected }
        if selected == nil { print("Discovery state: \(app.state.rawValue)\n\(app.debugDescription)") }
        XCTAssertNotNil(selected)
        return selected?.identifier ?? ""
    }

    private func assertTabsAboveDock(_ app: XCUIApplication) {
        let dock = app.descendants(matching: .any)["app.tabbar"]
        for id in ["portfolio", "market", "investors"] {
            let tab = app.buttons["today.tab.\(id)"]
            XCTAssertTrue(tab.isHittable)
            XCTAssertLessThan(tab.frame.maxY, dock.frame.minY)
        }
    }

    private func launch(scenario: String = "loaded", language: String = "en", appearance: String = "dark",
                        largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reset-state", "--ui-scenario=\(scenario)", "--ui-trading-fixture",
                               "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN",
                               "--ui-appearance", appearance]
        if scenario == "first-use" { app.launchArguments += ["-bsmart.portfolio-setup-complete.v1", "YES"] }
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"] }
        app.launch()
        XCTAssertTrue(app.staticTexts["discovery.heading"].waitForExistence(timeout: 10))
        XCTAssertTrue(people(app).firstMatch.waitForExistence(timeout: 5))
        return app
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
