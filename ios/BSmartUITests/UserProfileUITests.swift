import XCTest

final class UserProfileUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testProfileIsLastAndExampleAddressCannotReceiveFunds() {
        let app = launch()
        let ids = ["today", "smart", "feed", "portfolio"]
        let tabs = ids.map { app.buttons["app.tab." + $0] }
        for tab in tabs { XCTAssertTrue(tab.waitForExistence(timeout: 8)) }
        for index in 1..<tabs.count { XCTAssertLessThan(tabs[index - 1].frame.midX, tabs[index].frame.midX) }
        XCTAssertEqual(tabs.last?.label, "My profile")
        tabs.last?.tap()
        XCTAssertTrue(app.staticTexts["profile.nickname"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["profile.edit"].isHittable)
        app.buttons["profile.address"].tap()
        XCTAssertTrue(app.staticTexts["profile.address.full"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["profile.address.example-warning"].exists)
        XCTAssertFalse(app.buttons["profile.address.copy"].exists)
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

    func testEditPersistsAndCancelDoesNotSave() {
        let app = launch()
        app.buttons["app.tab.portfolio"].tap()
        let edit = app.buttons["profile.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        let nickname = app.textFields["profile.edit.nickname"]
        XCTAssertTrue(nickname.waitForExistence(timeout: 3))
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
