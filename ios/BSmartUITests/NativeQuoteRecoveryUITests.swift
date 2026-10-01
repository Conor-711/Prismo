import XCTest

final class NativeQuoteRecoveryUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testDeviceRedditQuotePreviewAndNavigationWithoutTradingOrPublishing() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Read-only check of the connected user's existing CRWD quote.")
        #else
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["app.tab.today"].waitForExistence(timeout: 60))
        app.buttons["app.tab.today"].tap()
        app.buttons["today.tab.activity"].tap()
        let rail = app.scrollViews["smart-updates.sources"]
        let source = app.buttons["smart-updates.platform.bsmart"]
        for _ in 0..<3 where !source.isHittable { rail.swipeRight() }
        XCTAssertTrue(source.isHittable)
        source.tap()
        let quote = app.buttons.matching(NSPredicate(format:
            "identifier == %@ AND label CONTAINS %@", "smart-updates.native-base", "u/BFLO-Retail")).firstMatch
        for _ in 0..<10 where !quote.isHittable {
            if quote.waitForExistence(timeout: 3), quote.isHittable { break }
            app.scrollViews["today.page.activity"].swipeUp()
        }
        XCTAssertTrue(quote.isHittable, app.debugDescription)
        let body = quote.staticTexts["smart-updates.native-base.body"]
        XCTAssertTrue(body.exists)
        XCTAssertFalse(body.label.contains("\n"))
        XCTAssertTrue(body.label.contains("pump and dump"))
        XCTAssertLessThanOrEqual(quote.frame.height, 96)
        let avatar = quote.images.matching(NSPredicate(format: "label CONTAINS %@", "BFLO-Retail")).firstMatch
        XCTAssertTrue(avatar.waitForExistence(timeout: 20), "Quote must render the author's image, not a text initial")
        quote.tap()
        XCTAssertTrue(app.buttons["detail.back"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["detail.back"].firstMatch.tap()
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        #endif
    }
}
