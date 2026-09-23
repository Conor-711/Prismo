import XCTest

final class GoogleSignInLiveUITests: XCTestCase {
    func testGoogleAuthorizationPageOpensWithoutWalletBackend() throws {
        continueAfterFailure = false
        guard ProcessInfo.processInfo.environment["BSMART_TEST_GOOGLE_OAUTH"] == "1" else {
            throw XCTSkip("Opt-in live Google authorization UI. Does not enter credentials or grant account access.")
        }
        let app = XCUIApplication()
        app.launchArguments = ["--use-fixture-data", "--ui-trading-fixture", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let skip = app.buttons["onboarding.skip"]
        if skip.waitForExistence(timeout: 5) { skip.tap() }
        let profile = app.buttons["app.tab.portfolio"]
        XCTAssertTrue(profile.waitForExistence(timeout: 20))
        profile.tap()
        let settings = app.buttons["portfolio.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        settings.tap()
        let account = app.buttons["settings.account"]
        if !account.waitForExistence(timeout: 3), settings.exists { settings.tap() }
        XCTAssertTrue(account.waitForExistence(timeout: 5))
        account.tap()
        let google = app.descendants(matching: .any)["account.signin.google"].firstMatch
        XCTAssertTrue(google.waitForExistence(timeout: 10))
        XCTAssertTrue(NSPredicate(format: "enabled == true").evaluate(with: google)
            || XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: google)], timeout: 20) == .completed)
        XCTAssertFalse(app.descendants(matching: .any)["account.signin.apple"].exists)
        google.tap()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let appContinue = app.alerts.buttons["Continue"]
        if appContinue.waitForExistence(timeout: 3) { appContinue.tap() }
        else if springboard.alerts.buttons["Continue"].waitForExistence(timeout: 3) {
            springboard.alerts.buttons["Continue"].tap()
        }
        let browser = XCUIApplication(bundleIdentifier: "com.apple.SafariViewService")
        let appEmail = app.webViews.textFields["Email or phone"]
        let browserEmail = browser.webViews.textFields["Email or phone"]
        XCTAssertTrue(appEmail.waitForExistence(timeout: 20) || browserEmail.waitForExistence(timeout: 10),
                      "Google's real sign-in page was not reached. No credential or account consent is automated.")
        XCTAssertFalse(app.staticTexts["account.signed-in"].exists)
        // Stop at credential entry. Full OAuth acceptance requires the user's own sign-in.
    }
}
