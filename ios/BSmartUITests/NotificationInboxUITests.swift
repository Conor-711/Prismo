import XCTest

final class NotificationInboxUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testHoldingsInboxReadStateEvidenceNavigationAndSettings() {
        let app = launch()
        XCTAssertFalse(app.buttons["today.settings"].exists)
        app.buttons["today.notifications"].tap()
        XCTAssertTrue(app.buttons["notifications.read-all"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["app.tabbar"].isHittable)
        app.buttons["notifications.filter.holdings"].tap()
        app.buttons["notifications.unread-only"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "notification.row.account:")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["smart.account.evidence.detail"].waitForExistence(timeout: 5))
        app.buttons["detail.back"].tap()
        XCTAssertTrue(app.buttons["notifications.read-all"].waitForExistence(timeout: 5))
        app.buttons["notifications.read-all"].tap()
        XCTAssertTrue(app.staticTexts["You're all caught up"].waitForExistence(timeout: 5))
        app.buttons["detail.back"].tap()
        let bell = app.buttons["today.notifications"]
        XCTAssertTrue(bell.waitForExistence(timeout: 5))
        XCTAssertEqual(bell.value as? String, "0 unread")
        app.buttons["app.tab.portfolio"].tap()
        let settings = app.buttons["portfolio.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings.screen"].waitForExistence(timeout: 5))
    }

    func testEmptyInboxInChineseLightModeOffersDiscoveryAndHoldingEntry() {
        let app = launch(empty: true)
        app.buttons["today.notifications"].tap()
        XCTAssertTrue(app.staticTexts["暂无相关通知"].waitForExistence(timeout: 5))
        app.buttons["notifications.filter.tracked"].tap()
        XCTAssertTrue(app.staticTexts["暂无相关通知"].exists)
        let add = app.buttons["添加持仓"]
        XCTAssertTrue(add.isHittable)
        add.tap()
        XCTAssertTrue(app.descendants(matching: .any)["position-editor.screen"].waitForExistence(timeout: 5))
    }

    func testNewFollowersMoveToHomeInboxAndShareReadState() {
        let app = launch(followers: true)
        app.buttons["today.notifications"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "notification.row.follower:")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        app.scrollViews["notifications.filters"].swipeLeft()
        app.buttons["notifications.filter.followers"].tap()
        XCTAssertTrue(row.exists)
        XCTAssertTrue(app.staticTexts["Started following you"].exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "notification.row.account:")).firstMatch.exists)
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["feed.profile.screen"].waitForExistence(timeout: 5))
        app.buttons["detail.back"].tap()
        app.buttons["notifications.unread-only"].tap()
        XCTAssertTrue(app.staticTexts["You're all caught up"].waitForExistence(timeout: 5))
        XCTAssertFalse(row.exists)
        app.buttons["notifications.unread-only"].tap()
        XCTAssertTrue(row.exists)
    }

    private func launch(empty: Bool = false, followers: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reset-state", "--ui-scenario=\(empty ? "first-use" : "loaded")",
            "--ui-trading-fixture", "--ui-appearance", empty ? "light" : "dark",
            "-AppleLanguages", empty ? "(zh-Hans)" : "(en)", "-AppleLocale", empty ? "zh_CN" : "en_US"]
        if empty { app.launchArguments += ["-bsmart.portfolio-setup-complete.v1", "YES"] }
        if followers { app.launchArguments += ["--ui-follow-notification-fixture"] }
        app.launch()
        XCTAssertTrue(app.buttons["today.notifications"].waitForExistence(timeout: 10))
        return app
    }
}
