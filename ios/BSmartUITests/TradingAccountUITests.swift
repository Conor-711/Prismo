import XCTest

final class TradingAccountUITests: XCTestCase {
    func testGoogleOnlyAccountWithoutConfiguration() {
        checkAccountFlow(language: "en", appearance: "dark")
    }

    func testChineseGoogleOnlyAccountInLightMode() {
        checkAccountFlow(language: "zh-Hans", appearance: "light")
    }

    private func checkAccountFlow(language: String, appearance: String) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reset-state", "--ui-scenario=loaded", "--ui-trading-fixture",
                               "--ui-appearance", appearance,
                               "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        app.launch()
        let settings = app.buttons["today.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"), object: settings
        )], timeout: 10), .completed)
        settings.tap()
        let account = app.buttons["settings.account"]
        if !account.waitForExistence(timeout: 3), settings.exists { settings.tap() }
        XCTAssertTrue(account.waitForExistence(timeout: 5))
        account.tap()
        XCTAssertTrue(app.descendants(matching: .any)["account.signin.google"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["account.signin.apple"].exists)
        XCTAssertTrue(app.staticTexts["account.unavailable"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["account.deposit-info"].exists)
        XCTAssertFalse(app.buttons["account.deposit"].exists)
        XCTAssertFalse(app.staticTexts["account.signed-in"].exists)
    }
}
