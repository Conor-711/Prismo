import XCTest

final class RepresentativeWorksUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testTopRankReplacesPlatformArrowBelowPortraitInBothThemes() {
        for appearance in ["dark", "light"] {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-reset-state", "--ui-scenario=loaded", "--ui-trading-fixture",
                "--ui-appearance", appearance, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            app.launch()
            let directory = app.buttons["discovery.open-directory"]
            XCTAssertTrue(directory.waitForExistence(timeout: 10))
            directory.tap()
            let account = app.descendants(matching: .any)["smart.account.row.first"]
            XCTAssertTrue(account.waitForExistence(timeout: 5))
            account.tap()
            let badge = app.staticTexts["smart.account.top-rank"]
            XCTAssertTrue(badge.waitForExistence(timeout: 5))
            XCTAssertTrue(badge.label.contains("TOP 1%"), badge.label)
            XCTAssertTrue(badge.isHittable)
            let portrait = app.descendants(matching: .any)["smart.account.portrait"]
            let identity = app.descendants(matching: .any)["smart.account.identity"]
            XCTAssertTrue(identity.frame.contains(badge.frame))
            // Image accessibility bounds include cropped pixels; the bottom-aligned name
            // plus its 20pt inset locates the visible portrait edge.
            let name = app.staticTexts["smart.account.portrait.name"]
            XCTAssertGreaterThanOrEqual(badge.frame.minY, name.frame.maxY + 20)
            XCTAssertGreaterThan(badge.frame.midX, identity.frame.midX)
            XCTAssertFalse(portrait.staticTexts["smart.account.top-rank"].exists)
            XCTAssertEqual(app.staticTexts.matching(identifier: "smart.account.top-rank").count, 1)
            XCTAssertFalse(identity.links["Open public profile"].exists)
            XCTAssertFalse(app.descendants(matching: .any)["app.tabbar"].isHittable)
            app.terminate()
        }
    }

    func testPortraitReturnsAfterPullAndHistoryRemainsAccessibleInLightMode() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reset-state", "--ui-scenario=loaded", "--ui-trading-fixture",
                               "--ui-appearance", "light", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let smart = app.buttons["discovery.open-directory"]
        XCTAssertTrue(smart.waitForExistence(timeout: 8))
        smart.tap()
        let account = app.descendants(matching: .any)["smart.account.row.first"]
        XCTAssertTrue(account.waitForExistence(timeout: 5))
        account.tap()
        let portrait = app.descendants(matching: .any)["smart.account.portrait"]
        XCTAssertTrue(portrait.waitForExistence(timeout: 5))
        let authorName = app.staticTexts["smart.account.portrait.name"].label
        let original = portrait.frame
        let start = portrait.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        let end = start.withOffset(CGVector(dx: 0, dy: 140))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertEqual(portrait.frame.height, original.height, accuracy: 2)
        XCTAssertTrue(app.staticTexts["smart.account.portrait.name"].isHittable)
        let follow = app.buttons["smart.account.follow"]
        XCTAssertTrue(follow.isHittable, app.debugDescription)
        follow.tap()
        XCTAssertTrue(follow.label.contains("Tracking"))

        let method = app.descendants(matching: .any)["smart.account.methodology"]
        for _ in 0..<18 {
            if method.isHittable && method.frame.maxY < app.frame.height - 140 { break }
            // Stay outside the interactive chart while vertically scrolling the page.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.72))
                .press(forDuration: 0.01, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.25)))
        }
        XCTAssertTrue(method.isHittable)
        XCTAssertTrue(app.navigationBars.staticTexts[authorName].isHittable, app.debugDescription)
        XCTAssertTrue(follow.isHittable)
        XCTAssertFalse(app.buttons["app.tab.smart"].isHittable)
        method.tap()
        let limits = app.staticTexts.matching(NSPredicate(format: "label == %@",
            "Featured works are selected historical examples, not the author's portfolio return. Public views do not establish actual positions; past performance does not guarantee future results.")).firstMatch
        XCTAssertTrue(limits.exists)
        let history = app.descendants(matching: .any)["smart.account.history"]
        for _ in 0..<8 {
            if history.isHittable && history.frame.maxY < app.frame.height - 140 { break }
            app.swipeUp()
        }
        XCTAssertTrue(history.isHittable)
        history.tap()
        let evidenceRows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "smart.account.history.item."))
        XCTAssertGreaterThan(evidenceRows.count, 0)
    }

    func testAuthorShowsPortraitThenSwitchesRepresentativeChartInPlace() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reset-state", "--ui-scenario=loaded", "--ui-trading-fixture",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let smart = app.buttons["discovery.open-directory"]
        XCTAssertTrue(smart.waitForExistence(timeout: 8))
        smart.tap()
        let account = app.descendants(matching: .any)["smart.account.row.first"]
        XCTAssertTrue(account.waitForExistence(timeout: 5))
        account.tap()
        let portrait = app.descendants(matching: .any)["smart.account.portrait"]
        XCTAssertTrue(portrait.waitForExistence(timeout: 5))
        XCTAssertTrue(portrait.isHittable, "\(portrait.frame)\n\(app.debugDescription)")
        XCTAssertFalse(app.segmentedControls["smart.account.detail.section"].exists)
        XCTAssertTrue(app.buttons["smart.account.follow"].isHittable, app.debugDescription)
        let title = app.staticTexts["smart.account.portrait.name"]
        XCTAssertTrue(title.exists)
        XCTAssertLessThan(portrait.frame.maxY, app.frame.height / 2)
        let selectors = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "account.work.select."))
        for _ in 0..<8 {
            if selectors.firstMatch.isHittable { break }
            app.swipeUp()
        }
        XCTAssertEqual(selectors.count, 3)
        XCTAssertFalse(app.descendants(matching: .any)["account.work.entry"].exists)
        XCTAssertFalse(app.staticTexts["Historical price change, not account ROI."].exists)
        XCTAssertFalse(app.staticTexts["Latest available views, not verified holdings."].exists)
        XCTAssertTrue(app.staticTexts["account.work.performance"].exists)
        let performance = app.staticTexts["account.work.performance"]
        let mode = app.buttons["account.work.candles"]
        XCTAssertGreaterThanOrEqual(mode.frame.minX, performance.frame.maxX)
        XCTAssertLessThan(abs(mode.frame.midY - performance.frame.midY), 24)
        let first = selectors.element(boundBy: 0)
        let second = selectors.element(boundBy: 1)
        XCTAssertTrue(first.isSelected)
        second.tap()
        XCTAssertTrue(second.isSelected)
        XCTAssertFalse(first.isSelected)
        let symbol = String(second.identifier.dropFirst("account.work.select.".count))
        for _ in 0..<3 {
            if app.buttons["account.work.marker.0"].isHittable { break }
            app.swipeUp()
        }
        XCTAssertEqual(app.staticTexts["account.work.ticker"].label, symbol)
        let chart = app.descendants(matching: .any).matching(identifier: "account.work.chart").firstMatch
        XCTAssertEqual(app.staticTexts.matching(identifier: "account.work.ticker").count, 1)
        XCTAssertTrue(chart.exists)
        let bubble = app.buttons["account.work.marker.1"]
        let plot = app.descendants(matching: .any)["account.work.chart.plot"]
        for _ in 0..<12 {
            let frame = plot.frame
            if frame.minY >= 130 && frame.maxY <= app.frame.height - 140 { break }
            let up = frame.minY >= 130
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: up ? 0.7 : 0.35))
                .press(forDuration: 0.01, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: up ? 0.35 : 0.7)))
        }
        XCTAssertTrue(bubble.isHittable, app.debugDescription)
        bubble.tap()
        XCTAssertTrue(app.buttons["account.work.opinion.1"].isSelected)
        XCTAssertFalse(app.buttons["account.work.opinion.0"].isSelected)
        XCTAssertTrue(app.staticTexts["account.work.selected-thesis"].exists)
        let line = app.buttons["account.work.line"]
        // Scroll outside the interactive plot and clear both navigation and follow dock.
        for _ in 0..<12 {
            let frame = line.frame
            if line.isHittable && frame.minY >= 130 && frame.maxY <= app.frame.height - 140 { break }
            let up = frame.minY >= 130
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: up ? 0.7 : 0.35))
                .press(forDuration: 0.01, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: up ? 0.35 : 0.7)))
        }
        XCTAssertTrue(line.isHittable)
        line.tap()
        XCTAssertTrue(line.isSelected)
        XCTAssertTrue(app.buttons["account.work.marker.0"].exists)
        XCTAssertFalse(app.buttons["app.tab.smart"].isHittable)
    }
}
