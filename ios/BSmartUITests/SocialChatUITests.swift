import XCTest

final class SocialChatUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testGlobalUnreadDotClearsAfterMessagesLoad() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reset-state", "--ui-scenario=loaded", "--ui-trading-fixture", "--ui-chat-fixture",
                               "--ui-chat-unread-fixture", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let friends = app.buttons["app.tab.friends"]
        XCTAssertTrue(friends.waitForExistence(timeout: 8))
        let unread = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Unread messages"), object: friends)
        XCTAssertEqual(XCTWaiter.wait(for: [unread], timeout: 5), .completed)
        friends.tap()
        let global = app.buttons["friends.global"]
        XCTAssertTrue(global.waitForExistence(timeout: 5))
        let roomUnread = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Unread messages"), object: global)
        XCTAssertEqual(XCTWaiter.wait(for: [roomUnread], timeout: 5), .completed)
        XCTAssertTrue(global.staticTexts["You: Same here"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "global-chat-unread-dot"; screenshot.lifetime = .keepAlways; add(screenshot)

        global.tap()
        XCTAssertTrue(app.staticTexts["What are you watching in the market today?"].firstMatch.waitForExistence(timeout: 5))
        app.navigationBars["Global Chat"].buttons.firstMatch.tap()
        XCTAssertTrue(global.waitForExistence(timeout: 5))
        XCTAssertNotEqual(global.value as? String, "Unread messages")
        XCTAssertNotEqual(friends.value as? String, "Unread messages")
    }

    func testGlobalChatReplyTypingSendAndDismissKeyboard() {
        let app = launch()
        let alice = app.staticTexts["What are you watching in the market today?"].firstMatch
        XCTAssertTrue(alice.waitForExistence(timeout: 5))
        alice.swipeLeft()
        XCTAssertTrue(app.descendants(matching: .any)["friends.reply-preview"].firstMatch.waitForExistence(timeout: 3))
        let field = app.descendants(matching: .any)["friends.composer"].firstMatch
        field.tap()
        field.typeText("Checking the latest earnings today")
        XCTAssertTrue((field.value as? String ?? "").contains("latest earnings"))
        app.navigationBars.staticTexts["Global Chat"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        app.buttons["friends.send"].tap()
        XCTAssertTrue(app.staticTexts["Checking the latest earnings today"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["friends.reply-preview"].firstMatch.exists)
        XCTAssertTrue(app.buttons["friends.attach"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "global-chat-reply"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    func testLongPressOffersReplyAndCopy() {
        let app = launch()
        let message = app.staticTexts["What are you watching in the market today?"].firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        message.press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Reply"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Copy"].exists)
        app.buttons["Reply"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["friends.reply-preview"].firstMatch.waitForExistence(timeout: 3))
    }

    func testSenderAvatarOpensPublicProfile() {
        let app = launch()
        let avatar = app.buttons["friends.message.profile.11111111-1111-4111-8111-111111111111"]
        XCTAssertTrue(avatar.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(avatar.frame.width, 42)
        avatar.tap()
        XCTAssertTrue(app.descendants(matching: .any)["feed.profile.screen"].firstMatch
            .waitForExistence(timeout: 5))
        app.buttons["detail.back"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["friends.chat.screen"].firstMatch
            .waitForExistence(timeout: 5))
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reset-state", "--ui-scenario=loaded", "--ui-trading-fixture", "--ui-chat-fixture",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["app.tab.friends"].waitForExistence(timeout: 8))
        app.buttons["app.tab.friends"].tap()
        let global = app.buttons["friends.global"]
        XCTAssertTrue(global.waitForExistence(timeout: 5))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: global)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        global.tap()
        return app
    }
}
