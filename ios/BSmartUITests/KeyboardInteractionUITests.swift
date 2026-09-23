import XCTest

final class KeyboardInteractionUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testProfileSheetDismissesOutsideSwitchesFieldsAndSavesWithOneTap() {
        let app = launch()
        app.buttons["app.tab.portfolio"].tap()
        app.buttons["profile.edit"].tap()
        let name = app.textFields["profile.edit.nickname"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        name.typeText(" Test")
        let bio = app.descendants(matching: .any)["profile.edit.bio"].firstMatch
        bio.tap()
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        bio.typeText("Keyboard draft")
        XCTAssertTrue((bio.value as? String ?? "").contains("Keyboard draft"))
        app.navigationBars.staticTexts["Edit profile"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertTrue((bio.value as? String ?? "").contains("Keyboard draft"))
        name.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        app.buttons["profile.save"].tap()
        XCTAssertTrue(app.staticTexts["profile.nickname"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["profile.bio"].label.contains("Keyboard draft"))
    }

    func testSearchClearingAndResultTapStillWorkWhileEditing() {
        let app = launch()
        app.buttons["app.tab.search"].tap()
        let field = app.textFields["search.input"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("NVDA")
        XCTAssertTrue(app.buttons["search.result.ticker:NVDA"].waitForExistence(timeout: 8))
        app.buttons["search.clear"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        field.typeText("BTC")
        let result = app.buttons["search.result.ticker:BTC"]
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        result.tap()
        XCTAssertTrue(app.descendants(matching: .any)["ticker-intelligence.BTC"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
    }

    func testDecimalKeyboardDismissesWithoutChangingAmount() {
        let app = launch()
        app.buttons["app.tab.portfolio"].tap()
        app.buttons["Add ticker"].tap()
        let amount = app.textFields["position-editor.field.Shares"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        for _ in 0..<3 where !amount.isHittable { app.swipeUp() }
        amount.tap(); amount.typeText("12.5")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        app.navigationBars.staticTexts["Add ticker"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertEqual(amount.value as? String, "12.5")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["profile.edit"].waitForExistence(timeout: 3))
    }

    func testSmartSearchKeepsLatestQueryAndSwitchingSectionsClearsIt() {
        let app = launch()
        app.buttons["discovery.open-directory"].tap()
        let field = app.textFields["smart.search"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Serenity")
        XCTAssertTrue(app.staticTexts["Serenity"].waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "Serenity")
        app.descendants(matching: .any)["smart.section.money"].tap()
        XCTAssertNotEqual(field.value as? String, "Serenity")
        app.descendants(matching: .any)["smart.section.accounts"].tap()
        XCTAssertTrue(app.buttons["smart.account.row.first"].waitForExistence(timeout: 5))
    }

    func testTickerDirectoryFiltersAndClearsWithoutLosingKeyboardFocus() {
        let app = launch()
        app.buttons["app.tab.portfolio"].tap()
        let tab = app.buttons["portfolio.tab.allTickers"]
        for _ in 0..<3 where !tab.isHittable { app.swipeUp() }
        tab.tap()
        let field = app.textFields["portfolio.ticker-search"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        for _ in 0..<3 where !field.isHittable { app.swipeUp() }
        field.tap(); field.typeText("NVDA")
        XCTAssertTrue(app.buttons["portfolio.ticker.NVDA"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["portfolio.ticker.BTC"].waitForNonExistence(timeout: 3))
        app.buttons["Clear"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        field.typeText("BTC")
        let result = app.buttons["portfolio.ticker.BTC"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        XCTAssertTrue(app.descendants(matching: .any)["ticker-intelligence.BTC"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reset-state", "--ui-scenario=loaded", "--ui-trading-fixture", "--ui-search-fixture",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["app.tab.portfolio"].waitForExistence(timeout: 10))
        return app
    }
}
