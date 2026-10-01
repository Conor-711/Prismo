import XCTest

final class TodayInvestorActivityUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testGroupedPlatformSourcesChooseIndividualNetwork() {
        let app = launch()
        let platform = app.buttons["smart-updates.platform.social"]
        XCTAssertTrue(platform.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["smart-updates.platform.x"].exists)
        platform.tap()
        XCTAssertTrue(app.buttons["smart-updates.platform-choice.x"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["smart-updates.platform-choice.youtube"].exists)
        XCTAssertTrue(app.buttons["smart-updates.platform-choice.reddit"].exists)
        app.buttons["smart-updates.platform-choice.youtube"].tap()
        XCTAssertTrue(platform.label.contains("YouTube"))
        platform.tap()
        app.buttons["smart-updates.platform-choice.social"].tap()
        XCTAssertFalse(platform.label.contains("YouTube"))
    }

    func testInvestorCardsTrackingAndEvidenceRoute() {
        let app = launch()
        XCTAssertTrue(app.buttons["today.tab.activity"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["today.standalone.title"].exists)
        XCTAssertTrue(app.buttons["smart-updates.sort"].exists)
        app.buttons["smart-updates.platform.social"].tap()
        app.buttons["smart-updates.platform-choice.x"].tap()
        let card = investorCard(in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let entries = card.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "smart-updates.evidence."))
        XCTAssertGreaterThan(entries.count, 0)
        XCTAssertLessThanOrEqual(entries.count, 2)
        let performance = card.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "smart-updates.performance.")).firstMatch
        XCTAssertTrue(performance.exists)
        let wins = performance.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "smart-updates.wins.")).firstMatch
        let losses = performance.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "smart-updates.losses.")).firstMatch
        XCTAssertEqual(wins.exists, losses.exists)
        XCTAssertTrue(card.staticTexts["看多"].exists)
        XCTAssertFalse(card.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "smart-updates.track.")).firstMatch.exists)
        let followingOnly = app.descendants(matching: .any)["smart-updates.following-only"]
        XCTAssertTrue(followingOnly.exists)
        followingOnly.tap()
        XCTAssertTrue(app.descendants(matching: .any)["smart-updates.empty"].waitForExistence(timeout: 3))
        followingOnly.tap()
        XCTAssertTrue(investorCard(in: app).waitForExistence(timeout: 3))
        screenshot(app, "Smart updates - investor cards - Chinese dark")

        entries.firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["smart.account.evidence.detail"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()

        XCTAssertFalse(card.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "smart-updates.open.")).firstMatch.exists)

        XCTAssertFalse(app.textFields["smart-updates.search"].exists)
    }

    func testConsecutiveInvestorUpdatesExpandInPlace() {
        let app = launch()
        let burst = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "smart-updates.burst.")).firstMatch
        let page = app.scrollViews["today.page.activity"]
        for _ in 0..<8 where !burst.isHittable {
            page.swipeUp()
        }
        XCTAssertTrue(burst.isHittable)
        if burst.frame.midY > page.frame.maxY - 150 {
            page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                .press(forDuration: 0.1, thenDragTo:
                    page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.58)))
        }
        XCTAssertTrue(burst.isHittable)
        XCTAssertTrue(burst.label.contains("还有"))
        XCTAssertFalse(burst.label.contains("该主体"))
        XCTAssertFalse(app.staticTexts["研究估算"].exists)
        screenshot(app, "Consecutive investor updates collapsed")
        burst.tap()
        XCTAssertTrue(burst.label.contains("收起动态"))
        screenshot(app, "Consecutive investor updates expanded")
        burst.tap()
        XCTAssertTrue(burst.label.contains("还有"))
    }

    func testDiscoveryWithoutHoldingsAndFiltersInLightMode() {
        let app = launch(scenario: "first-use", language: "en", appearance: "light")
        let source = app.buttons["smart-updates.filters"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["smart-updates.platform.social"].exists)
        screenshot(app, "Smart updates - light English without holdings")
        app.buttons["smart-updates.platform.social"].tap()
        app.buttons["smart-updates.platform-choice.x"].tap()
        XCTAssertTrue(investorCard(in: app).waitForExistence(timeout: 3))
        app.buttons["smart-updates.sort"].tap()
        app.buttons["smart-updates.sort.trending"].tap()
        XCTAssertTrue(app.buttons["smart-updates.sort"].exists)
    }

    func testInstitutionAndCelebrityHoldingsShowAssetInformation() {
        let app = launch()
        let sources = app.scrollViews["smart-updates.sources"]
        XCTAssertTrue(sources.waitForExistence(timeout: 5))
        sources.swipeLeft()
        sources.swipeLeft()
        for source in ["celebrities", "institutions"] {
            let filter = app.buttons["smart-updates.platform.\(source)"]
            XCTAssertTrue(filter.waitForExistence(timeout: 5))
            filter.tap()
            let asset = app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "feed.holding-asset.")).firstMatch
            XCTAssertTrue(asset.waitForExistence(timeout: 5))
            screenshot(app, "\(source) holding asset information")
            let profileLink = app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "subject-activity.profile.")).firstMatch
            XCTAssertTrue(profileLink.exists)
            profileLink.tap()
            XCTAssertTrue(app.descendants(matching: .any)["subject.profile.portrait"]
                .waitForExistence(timeout: 5))
            XCTAssertTrue(app.descendants(matching: .any)["subject.profile.assets"].exists)
            screenshot(app, "\(source) shared investor profile")
            app.buttons["detail.back"].tap()
        }
    }

    func testPoliticianProfileHistoryAndFollowingFilter() {
        let app = launch()
        app.buttons["smart-updates.platform.politicians"].tap()
        let profileLink = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "subject-activity.profile.")).firstMatch
        XCTAssertTrue(profileLink.waitForExistence(timeout: 5))
        profileLink.tap()
        let profile = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "subject.profile.detail.")).firstMatch
        XCTAssertTrue(profile.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["subject.profile.identity"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["subject.profile.performance"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["subject.profile.activity"].exists)
        app.buttons["subject.profile.filter.trade"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "subject-activity.event.")).firstMatch.exists)
        screenshot(app, "Politician subject profile")

        app.buttons["subject.profile.follow"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.descendants(matching: .any)["smart-updates.following-only"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "subject-activity.actor.")).firstMatch
            .waitForExistence(timeout: 5))
    }

    func testActivityScrollKeepsBottomContentVisible() {
        let app = launch()
        let page = app.scrollViews["today.page.activity"]
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        page.swipeUp()
        screenshot(app, "Activity scrolled to bottom safe area")
        XCTAssertEqual(page.frame.maxY, app.windows.firstMatch.frame.maxY, accuracy: 1)
        XCTAssertTrue(app.buttons["smart-updates.sort"].exists)

        app.buttons["today.tab.assets"].tap()
        let assets = app.scrollViews["today.page.assets"]
        XCTAssertTrue(assets.waitForExistence(timeout: 5))
        XCTAssertEqual(assets.frame.maxY, app.windows.firstMatch.frame.maxY, accuracy: 1)
    }

    func testNoDataRetainsSectionAndEmptyState() {
        let app = launch(scenario: "no-signals")
        XCTAssertTrue(app.descendants(matching: .any)["smart-updates.empty"].waitForExistence(timeout: 5))
        XCTAssertFalse(investorCard(in: app).exists)
    }

    private func investorCard(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "smart-updates.investor.")).firstMatch
    }

    private func evidence(_ source: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "smart-updates.evidence.\(source).")).firstMatch
    }

    private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launch(scenario: String = "loaded", language: String = "zh-Hans",
                        appearance: String = "dark") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reset-state", "--ui-scenario=\(scenario)", "--ui-trading-fixture",
                               "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN",
                               "--ui-appearance", appearance]
        if scenario == "first-use" { app.launchArguments += ["-bsmart.portfolio-setup-complete.v1", "YES"] }
        app.launch()
        return app
    }
}
