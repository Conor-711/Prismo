import XCTest

final class OpeningSettlementUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testDeviceOriginalAAPLOpeningShowsSettlementWithoutTrading() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Read-only test of the connected user's existing opening and exit fills.")
        #else
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["app.tab.today"].waitForExistence(timeout: 60))
        app.buttons["app.tab.today"].tap()
        app.buttons["today.tab.activity"].tap()
        let rail = app.scrollViews["smart-updates.sources"]
        let source = app.buttons["smart-updates.platform.bsmart"]
        for _ in 0..<3 where !source.isHittable { rail.swipeRight() }
        source.tap()
        var expanded: Set<String> = []
        var original: XCUIElement?
        for _ in 0..<24 {
            let panels = app.descendants(matching: .any).matching(identifier: "smart-updates.native-trade.aapl")
            original = panels.allElementsBoundByIndex.first {
                let entry = $0.staticTexts["smart-updates.native-trade.metric.Trade entry price"]
                return entry.exists && entry.label == "$332.48"
            }
            if let original, original.isHittable { break }
            let bursts = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "smart-updates.burst."))
            if let button = bursts.allElementsBoundByIndex.first(where: { $0.isHittable && !expanded.contains($0.identifier) }) {
                expanded.insert(button.identifier)
                button.tap()
            } else { app.scrollViews["today.page.activity"].swipeUp() }
        }
        let panel = try XCTUnwrap(original, app.debugDescription)
        XCTAssertTrue(panel.isHittable)
        let entry = panel.staticTexts["smart-updates.native-trade.metric.Trade entry price"]
        let exit = panel.staticTexts["smart-updates.native-trade.metric.Exit price"]
        let amount = panel.staticTexts["smart-updates.native-trade.metric.Open amount"]
        XCTAssertEqual(amount.label, "$11.97")
        XCTAssertEqual(entry.label, "$332.48")
        XCTAssertEqual(exit.label, "$331.85")
        XCTAssertEqual(panel.staticTexts["smart-updates.native-trade.pnl"].label, "-$0.024832")
        XCTAssertLessThanOrEqual(abs(entry.frame.minY - exit.frame.minY), 1)
        XCTAssertLessThanOrEqual(entry.frame.maxX, exit.frame.minX)
        XCTAssertTrue(panel.buttons["trade.open.aapl"].exists)
        #endif
    }
}
