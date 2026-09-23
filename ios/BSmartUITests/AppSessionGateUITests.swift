import XCTest

final class AppSessionGateUITests: XCTestCase {
    func testProviderButtonsUseAppLanguageEvenWhenDeviceLanguageDiffers() {
        continueAfterFailure = false
        for (language, deviceLanguage, appearance, appleTitle, googleTitle) in [
            ("en", "zh-Hans", "dark", "Continue with Apple", "Continue with Google"),
            ("zh-Hans", "en", "light", "使用 Apple 继续", "使用 Google 继续")
        ] {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-reset-state", "--ui-scenario=loaded", "--ui-auth-gate", "--ui-trading-fixture",
                "--ui-appearance", appearance, "-bsmart.app-language", language, "-AppleLanguages", "(\(deviceLanguage))"]
            app.launch()
            let apple = app.buttons["account.signin.apple"]
            let google = app.buttons["account.signin.google"]
            XCTAssertTrue(apple.waitForExistence(timeout: 10))
            XCTAssertEqual(apple.label, appleTitle)
            XCTAssertEqual(google.label, googleTitle)
            XCTAssertEqual(apple.frame.width, google.frame.width, accuracy: 1)
            XCTAssertEqual(apple.frame.height, google.frame.height, accuracy: 1)
            XCTAssertGreaterThanOrEqual(apple.frame.minY, google.frame.maxY)
            app.terminate()
        }
    }

    func testTestLoginEntersContentAndExitReturnsToRootLogin() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reset-state", "--ui-scenario=loaded", "--ui-auth-gate",
            "--ui-trading-fixture", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let testLogin = app.buttons["account.signin.test"]
        XCTAssertTrue(testLogin.waitForExistence(timeout: 10))
        testLogin.tap()
        XCTAssertTrue(app.buttons["app.tab.today"].waitForExistence(timeout: 10))
        app.buttons["app.tab.portfolio"].tap()
        let settings = app.buttons["portfolio.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let exit = app.buttons["settings.test-signout"]
        XCTAssertTrue(exit.waitForExistence(timeout: 5))
        exit.tap()
        assertLocked(app)
        XCTAssertTrue(testLogin.exists)
        testLogin.tap()
        XCTAssertTrue(app.buttons["app.tab.today"].waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        assertLocked(app)
    }

    func testSignedOutLaunchCannotReachContentOrDismissLogin() {
        continueAfterFailure = false
        for language in ["en", "zh-Hans"] {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-reset-state", "--ui-scenario=loaded", "--ui-auth-gate",
                "--ui-section=portfolio", "--ui-trading-fixture", "-AppleLanguages", "(\(language))"]
            app.launch()
            assertLocked(app)
            app.swipeDown()
            assertLocked(app)
            app.terminate()
            app.launch()
            assertLocked(app)
            app.terminate()
        }
    }

    private func assertLocked(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["account.signin.google"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["app.tab.today"].exists)
        XCTAssertFalse(app.buttons["app.tab.portfolio"].exists)
        XCTAssertFalse(app.otherElements["onboarding.screen"].exists)
        XCTAssertFalse(app.buttons["today.notifications"].exists)
        XCTAssertTrue(app.navigationBars.buttons.allElementsBoundByIndex.isEmpty)
    }
}
