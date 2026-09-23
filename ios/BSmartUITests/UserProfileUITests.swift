import XCTest

final class UserProfileUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testProfileDefaultsToAppHoldingsAndDepositWithAddressOnlyInSettings() {
        let app = launch()
        let ids = ["today", "feed", "search", "portfolio"]
        let tabs = ids.map { app.buttons["app.tab." + $0] }
        for tab in tabs { XCTAssertTrue(tab.waitForExistence(timeout: 8)) }
        for index in 1..<tabs.count { XCTAssertLessThan(tabs[index - 1].frame.midX, tabs[index].frame.midX) }
        XCTAssertEqual(tabs.last?.label, "My profile")
        tabs.last?.tap()
        XCTAssertTrue(app.staticTexts["profile.nickname"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["profile.edit"].isHittable)
        let avatar = app.descendants(matching: .any)["profile.avatar"]
        let name = app.staticTexts["profile.nickname"]
        XCTAssertGreaterThanOrEqual(name.frame.minX, avatar.frame.maxX)
        XCTAssertLessThanOrEqual(app.buttons["profile.edit"].frame.midX, avatar.frame.maxX + 16)
        XCTAssertLessThanOrEqual(name.frame.maxX, app.buttons["profile.ai.open"].frame.minX)
        XCTAssertLessThan(abs(name.frame.midY - avatar.frame.midY), 44)
        XCTAssertFalse(app.buttons["profile.address"].exists)
        let accountSwitch = app.buttons["portfolio.account.switch"]
        XCTAssertEqual(accountSwitch.value as? String, "Internal account")
        let accountBalance = app.staticTexts["portfolio.account.balance-value"]
        XCTAssertLessThan(abs(accountBalance.frame.midY - accountSwitch.frame.midY), 12)
        XCTAssertFalse(app.descendants(matching: .any)["wallet.hypercore-balances"].exists)
        let deposit = app.buttons["portfolio.deposit"]
        XCTAssertTrue(deposit.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(deposit.isHittable)
        XCTAssertGreaterThanOrEqual(deposit.frame.height, 44)
        XCTAssertLessThan(deposit.frame.maxY, app.buttons["app.tab.portfolio"].frame.minY)
        deposit.tap()
        XCTAssertTrue(app.descendants(matching: .any)["portfolio.deposit.screen"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Sign in"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["portfolio.settings"].tap()
        XCTAssertTrue(app.buttons["settings.wallet"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["settings.wallet.address"].exists, "Never display an example funding address for guests")
        for id in ["notifications", "data-methodology", "risk-disclosure", "reset-local-data"] {
            XCTAssertFalse(app.descendants(matching: .any)["settings." + id].exists)
        }
        app.buttons["Done"].tap()
        let page = app.scrollViews["portfolio.page.holdings"]
        for _ in 0..<4 {
            if app.buttons["portfolio.tab.allTickers"].isHittable { break }
            page.swipeUp()
        }
        for section in ["watchlist", "holdings", "allTickers"] {
            let tab = app.buttons["portfolio.tab." + section]
            XCTAssertTrue(tab.isHittable)
            tab.tap()
            XCTAssertTrue(tab.isSelected)
        }
        XCTAssertTrue(app.textFields["portfolio.ticker-search"].exists)
    }

    func testExternalAccountAndBrokerageConnectionsRemainAvailable() {
        let app = launch()
        app.buttons["app.tab.portfolio"].tap()
        let accountSwitch = app.buttons["portfolio.account.switch"]
        XCTAssertTrue(accountSwitch.waitForExistence(timeout: 5))
        let inAppScreenshot = XCTAttachment(screenshot: app.screenshot())
        inAppScreenshot.name = "Profile in-app balance switch"
        inAppScreenshot.lifetime = .keepAlways
        add(inAppScreenshot)
        accountSwitch.tap()
        XCTAssertEqual(accountSwitch.value as? String, "External account")
        let externalScreenshot = XCTAttachment(screenshot: app.screenshot())
        externalScreenshot.name = "Profile external balance switch"
        externalScreenshot.lifetime = .keepAlways
        add(externalScreenshot)
        XCTAssertTrue(app.descendants(matching: .any)["portfolio.value-chart"].exists)
        XCTAssertTrue(app.buttons["portfolio.brokerage-connections"].exists)
        accountSwitch.tap()
        XCTAssertEqual(accountSwitch.value as? String, "Internal account")
        XCTAssertTrue(app.buttons["portfolio.deposit"].isHittable)
    }

    func testExternalHoldingsUseCompactFourColumnTable() {
        let app = launch()
        app.buttons["app.tab.portfolio"].tap()
        let accountSwitch = app.buttons["portfolio.account.switch"]
        XCTAssertTrue(accountSwitch.waitForExistence(timeout: 5))
        accountSwitch.tap()
        let page = app.scrollViews["portfolio.page.holdings"]
        let row = app.buttons["portfolio.entry.NVDA"]
        for _ in 0..<4 where !row.isHittable { page.swipeUp() }
        XCTAssertTrue(row.isHittable, app.debugDescription)
        XCTAssertTrue(app.staticTexts["Qty / value"].exists)
        XCTAssertTrue(app.staticTexts["Price / cost"].exists)
        XCTAssertTrue(app.staticTexts["P&L"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Profile holdings compact table"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testEditPersistsAndCancelDoesNotSave() {
        let app = launch()
        app.buttons["app.tab.portfolio"].tap()
        let edit = app.buttons["profile.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        let nickname = app.textFields["profile.edit.nickname"]
        XCTAssertTrue(nickname.waitForExistence(timeout: 3))
        Thread.sleep(forTimeInterval: 0.5)
        let editorScreenshot = XCTAttachment(screenshot: app.screenshot())
        editorScreenshot.name = "Profile editor"
        editorScreenshot.lifetime = .keepAlways
        add(editorScreenshot)
        replace(nickname, with: "Casey")
        app.buttons["profile.save"].tap()
        XCTAssertEqual(app.staticTexts["profile.nickname"].label, "Casey")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["app.tab.portfolio"].waitForExistence(timeout: 8))
        app.buttons["app.tab.portfolio"].tap()
        XCTAssertTrue(app.staticTexts["profile.nickname"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["profile.nickname"].label, "Casey")
        app.buttons["profile.edit"].tap()
        replace(app.textFields["profile.edit.nickname"], with: "Discarded")
        app.buttons["Cancel"].tap()
        XCTAssertEqual(app.staticTexts["profile.nickname"].label, "Casey")
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reset-state", "--ui-scenario=loaded", "--ui-trading-fixture",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["app.tab.portfolio"].waitForExistence(timeout: 8))
        return app
    }

    private func replace(_ field: XCUIElement, with value: String) {
        field.tap()
        let previous = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + value)
    }
}
