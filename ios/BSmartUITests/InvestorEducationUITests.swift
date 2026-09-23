import XCTest

final class InvestorEducationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testEntryCaseAndHomeSelectionSurviveReturn() {
        checkFlow(language: "zh-Hans", appearance: "dark")
    }

    func testEnglishLightModeEducation() {
        checkFlow(language: "en", appearance: "light")
    }

    private func checkFlow(language: String, appearance: String) {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reset-state", "--ui-scenario=loaded", "--ui-trading-fixture",
                               "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN",
                               "--ui-appearance", appearance]
        app.launch()
        let entry = app.buttons["discovery.education"]
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        XCTAssertEqual(entry.label, language == "en" ? "Questions about the rankings?" : "对排名有疑问？")
        let selected = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "discovery.person."))
            .allElementsBoundByIndex.first { $0.isSelected }?.identifier
        for _ in 0..<4 { if entry.isHittable { break }; app.swipeUp() }
        entry.tap()
        XCTAssertTrue(app.descendants(matching: .any)["education.page"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.otherElements["app.tabbar"].isHittable)
        XCTAssertTrue(app.staticTexts["1000+"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["education.platform.x"].isSelected)
        XCTAssertLessThan(app.buttons["education.platform.youtube"].frame.maxX,
                          app.buttons["education.platform.x"].frame.minX)
        XCTAssertLessThan(app.buttons["education.platform.x"].frame.maxX,
                          app.buttons["education.platform.reddit"].frame.minX)
        XCTAssertEqual(app.staticTexts["education.headline"].label,
                       language == "en" ? "Investing. Who should you follow?" : "投资，该追踪谁？")
        XCTAssertFalse(app.staticTexts["1283"].exists)
        XCTAssertFalse(app.staticTexts["bSmart 比较他们过去的选股表现，帮你找到值得关注的人。"].exists)
        for (id, count) in [("youtube", "300"), ("reddit", "192"), ("x", "1000+")] {
            let tab = app.buttons["education.platform.\(id)"]
            XCTAssertTrue(tab.isHittable)
            tab.tap()
            XCTAssertTrue(tab.isSelected)
            XCTAssertEqual(app.staticTexts["education.population"].label, count)
        }
        let reveal = app.buttons["education.reveal"]
        for _ in 0..<7 { if reveal.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(reveal.isHittable)
        reveal.tap()
        let result = app.staticTexts["education.return"]
        let predicate = NSPredicate(format: "label CONTAINS %@", "133.28")
        expectation(for: predicate, evaluatedWith: result)
        waitForExpectations(timeout: 5)
        let filter = app.buttons["education.filter"]
        for _ in 0..<5 { if filter.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(filter.isHittable)
        filter.tap()
        app.buttons["detail.back"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        if let selected { XCTAssertTrue(app.buttons[selected].isSelected) }
        XCTAssertTrue(app.otherElements["app.tabbar"].isHittable)
        app.terminate()
    }
}
