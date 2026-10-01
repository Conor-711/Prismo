import XCTest

final class TodaySourceSwitchUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testPreparedSourcesSwitchContentTogetherWithSelection() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reset-state", "--ui-scenario=loaded", "--ui-trading-fixture",
                               "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        verifySources(in: app)
    }

    func testDeviceSourceSwitchWithoutResetOrTrading() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Read-only connected-iPhone check; keeps the existing account and data.")
        #else
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["app.tab.today"].waitForExistence(timeout: 60))
        app.buttons["app.tab.today"].tap()
        app.buttons["today.tab.activity"].tap()
        verifySources(in: app)
        #endif
    }

    private func verifySources(in app: XCUIApplication) {
        let feed = app.descendants(matching: .any).matching(identifier: "smart-updates.feed").firstMatch
        XCTAssertTrue(feed.waitForExistence(timeout: 10))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", "loading"), object: feed)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
        let rail = app.scrollViews["smart-updates.sources"]
        for source in ["bsmart", "all", "politicians", "celebrities", "institutions", "celebrities", "politicians", "all"] {
            let button = app.buttons["smart-updates.platform.\(source)"]
            for _ in 0..<3 where !button.isHittable {
                if source == "all" || source == "bsmart" { rail.swipeRight() } else { rail.swipeLeft() }
            }
            XCTAssertTrue(button.isHittable)
            button.tap()
            XCTAssertTrue(button.isSelected)
            XCTAssertEqual(feed.value as? String, source)
            XCTAssertNotEqual(feed.value as? String, "loading")
            if ["politicians", "celebrities", "institutions"].contains(source) {
                let kind = ["politicians": "politician", "celebrities": "celebrity", "institutions": "institution"][source]!
                XCTAssertTrue(app.descendants(matching: .any).matching(
                    NSPredicate(format: "identifier BEGINSWITH %@", "subject-activity.actor.\(kind):")).firstMatch.exists)
            }
        }
        let social = app.buttons["smart-updates.platform.social"]
        for source in ["x", "youtube", "reddit", "social"] {
            for _ in 0..<3 where !social.isHittable { rail.swipeRight() }
            social.tap()
            app.buttons["smart-updates.platform-choice.\(source)"].tap()
            XCTAssertEqual(feed.value as? String, source)
        }
    }
}
