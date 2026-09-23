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
        XCTAssertGreaterThanOrEqual(avatars.count, 3)
        XCTAssertEqual(visiblePeople(app).count, 3)
        XCTAssertEqual(featured.frame.midX, app.scrollViews["discovery.pool"].frame.midX, accuracy: 2)
        capture(app, "Discovery - horizontal default")
        let original = selectedPerson(app)
        app.scrollViews["discovery.pool"].swipeLeft()
        XCTAssertNotEqual(selectedPerson(app), original)
        XCTAssertEqual(visiblePeople(app).count, 3)
        XCTAssertTrue(app.buttons["today.tab.portfolio"].isSelected)
        let forward = selectedPerson(app)
        app.scrollViews["discovery.pool"].swipeRight()
        XCTAssertNotEqual(selectedPerson(app), forward)
        assertTabsAboveDock(app)
        capture(app, "Discovery - people")
    }

    func testCarouselPortraitsOpenMatchingProfilesAndPreserveScrollPosition() {
        let app = launch()
        XCTAssertFalse(app.scrollViews["discovery.sectors"].exists)
        let original = selectedPerson(app)
        let viewport = app.scrollViews["discovery.pool"].frame
        let neighbor = visiblePeople(app).first { !$0.isSelected }!
        for id in [original, neighbor.identifier] {
            let avatar = app.buttons[id]
            let originalFrame = avatar.frame
            let authorName = avatar.label.components(separatedBy: ", ")[0]
            avatar.tap()
            let name = app.staticTexts["smart.account.portrait.name"]
            XCTAssertTrue(name.waitForExistence(timeout: 5))
            XCTAssertEqual(name.label, authorName)
            XCTAssertTrue(app.staticTexts["smart.account.top-rank"].exists)
            XCTAssertFalse(app.descendants(matching: .any)["app.tabbar"].isHittable)
            app.buttons["detail.back"].tap()
            XCTAssertTrue(avatar.waitForExistence(timeout: 5))
            XCTAssertEqual(selectedPerson(app), original)
            XCTAssertEqual(avatar.frame.midX, originalFrame.midX, accuracy: 2)
        }
        app.scrollViews["discovery.pool"].swipeLeft()
        XCTAssertNotEqual(selectedPerson(app), original)
        XCTAssertEqual(app.scrollViews["discovery.pool"].frame, viewport)
        XCTAssertFalse(app.staticTexts["smart.account.portrait.name"].exists)
    }

    func testProfileBrowseFollowAndHomeSelectionSurviveReturn() {
        let app = launch()
        let selected = app.buttons["discovery.person.x:1940360837547565056"]
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
        app.buttons["discovery.open-directory"].tap()
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
        if !app.buttons["detail.back"].exists {
            // Native search temporarily replaces the directory toolbar while editing.
            let endSearch = app.navigationBars.buttons.matching(
                NSPredicate(format: "label IN %@", ["Close", "Cancel"])).firstMatch
            XCTAssertTrue(endSearch.exists)
            endSearch.tap()
        }
        XCTAssertTrue(app.buttons["detail.back"].waitForExistence(timeout: 5))
        app.buttons["detail.back"].tap()
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
        for avatar in visiblePeople(app) {
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
        let chart = focus.descendants(matching: .any).matching(identifier: "discovery.story.chart").firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 15))
        XCTAssertTrue(focus.staticTexts["行情代表作"].exists)
        XCTAssertGreaterThanOrEqual(app.buttons["discovery.story.open"].frame.height, 60)
        XCTAssertFalse(focus.staticTexts["discovery.story.copy"].exists)
        let firstPrice = focus.descendants(matching: .any).matching(identifier: "discovery.story.first-price").firstMatch
        XCTAssertTrue(firstPrice.label.contains("2026.02.27"))
        XCTAssertFalse(focus.descendants(matching: .any)["discovery.story.dates"].exists)
        XCTAssertTrue(focus.descendants(matching: .any)["discovery.story.peak-gain"].exists)
        let education = app.buttons["discovery.education"]
        let heading = app.buttons["discovery.open-directory"]
        XCTAssertTrue(education.exists)
        XCTAssertLessThan(abs(education.frame.midY - heading.frame.midY), 8)
        XCTAssertGreaterThanOrEqual(education.frame.minX, heading.frame.maxX)
        XCTAssertTrue(firstPrice.label.contains("$54"))
        XCTAssertFalse(firstPrice.label.contains("53.69"))
        let peakPrice = focus.descendants(matching: .any)["discovery.story.peak-price"]
        XCTAssertTrue(peakPrice.label.contains("$129"))
        let nodes = focus.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'discovery.story.node.'"))
        XCTAssertGreaterThan(nodes.count, 0)
        XCTAssertLessThanOrEqual(nodes.count, 3)
        for node in nodes.allElementsBoundByIndex {
            XCTAssertGreaterThanOrEqual(node.frame.width, 44 - 0.001)
            XCTAssertTrue(chart.frame.contains(node.frame))
        }
        XCTAssertTrue(focus.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Score'")).allElementsBoundByIndex.isEmpty)
        nodes.firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["smart.account.evidence.detail"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["discovery.story.detail"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["app.tabbar"].isHittable)
        app.buttons["detail.back"].tap()
        XCTAssertTrue(app.buttons["discovery.story.open"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["app.tabbar"].isHittable)
        app.buttons["discovery.story.open"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["smart.account.evidence.detail"].waitForExistence(timeout: 5))
    }

    func testRepresentativeIntroFitsLargeTypeAndDirectoryHasWorkWithoutOpeningProfiles() {
        let app = launch(appearance: "light", largeText: true)
        let focus = app.descendants(matching: .any)["discovery.focus.x:1940360837547565056"]
        let chart = focus.descendants(matching: .any).matching(identifier: "discovery.story.chart").firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 15))
        XCTAssertFalse(focus.staticTexts["discovery.story.copy"].exists)
        XCTAssertLessThanOrEqual(chart.frame.maxX, focus.frame.maxX)
        XCTAssertGreaterThanOrEqual(chart.frame.minX, focus.frame.minX)
        app.scrollViews["discovery.pool"].swipeLeft()
        XCTAssertFalse(app.buttons["discovery.person.x:1940360837547565056"].isSelected)
        XCTAssertFalse(app.staticTexts["discovery.story.copy"].exists)
    }

    func testEducationEntrySharesHeadingRowAndOpensExistingEducation() {
        let app = launch(language: "zh-Hans")
        let entry = app.buttons["discovery.education"]
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        let title = app.staticTexts["discovery.education.title"]
        XCTAssertTrue(title.exists)
        XCTAssertLessThanOrEqual(entry.frame.width, 120.5)
        XCTAssertLessThanOrEqual(title.frame.height, 16)
        XCTAssertLessThanOrEqual(title.frame.maxX, entry.frame.maxX - 16)
        let heading = app.buttons["discovery.open-directory"]
        XCTAssertLessThan(abs(entry.frame.midY - heading.frame.midY), 8)
        XCTAssertGreaterThanOrEqual(entry.frame.minX, heading.frame.maxX)
        XCTAssertEqual(app.buttons.matching(identifier: "discovery.education").count, 1)
        entry.tap()
        XCTAssertTrue(app.descendants(matching: .any)["education.page"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["app.tabbar"].isHittable)
        app.buttons["detail.back"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
    }

    func testEnglishEducationButtonStaysCompactAndSingleLine() {
        let app = launch(language: "en")
        let entry = app.buttons["discovery.education"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        let title = app.staticTexts["discovery.education.title"]
        XCTAssertTrue(title.exists)
        XCTAssertEqual(title.label, "Ranking questions?")
        XCTAssertGreaterThanOrEqual(title.frame.height, 14)
        XCTAssertLessThanOrEqual(title.frame.height, 16)
        XCTAssertLessThanOrEqual(entry.frame.width, 144.5)
        XCTAssertLessThanOrEqual(title.frame.maxX, entry.frame.maxX - 16)
        XCTAssertGreaterThanOrEqual(entry.frame.height, 44)
        XCTAssertGreaterThanOrEqual(entry.frame.minX, app.buttons["discovery.open-directory"].frame.maxX)
        let directory = app.buttons["discovery.open-directory"]
        XCTAssertGreaterThanOrEqual(directory.frame.height, 44)
        directory.tap()
        XCTAssertTrue(app.descendants(matching: .any)["smart.account.row.first"].waitForExistence(timeout: 5))
    }

    private func waitForMotion(_ seconds: Double) {
        let elapsed = expectation(description: "Allow the native animation clock to advance")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { elapsed.fulfill() }
        wait(for: [elapsed], timeout: seconds + 2)
    }

    private func people(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "discovery.person."))
    }

    private func visiblePeople(_ app: XCUIApplication) -> [XCUIElement] {
        let viewport = app.scrollViews["discovery.pool"].frame
        return people(app).allElementsBoundByIndex.filter {
            viewport.intersection($0.frame).width > $0.frame.width / 2
        }
    }

    private func selectedPerson(_ app: XCUIApplication) -> String {
        let selected = people(app).allElementsBoundByIndex.first { $0.isSelected }
        if selected == nil { print("Discovery state: \(app.state.rawValue)\n\(app.debugDescription)") }
        XCTAssertNotNil(selected)
        return selected?.identifier ?? ""
    }

    private func assertTabsAboveDock(_ app: XCUIApplication) {
        let dock = app.descendants(matching: .any)["app.tabbar"]
        XCTAssertTrue(dock.isHittable)
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
