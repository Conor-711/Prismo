import XCTest
@testable import BSmart

final class OnboardingContentTests: XCTestCase {
    func testFeaturedStoryUsesSerenityAAOIRecord() throws {
        let story = try XCTUnwrap(OnboardingFeaturedStory.story)

        XCTAssertEqual(story.account.id, OnboardingFeaturedStory.authorID)
        XCTAssertEqual(story.account.handle, "@aleabitoreddit")
        XCTAssertEqual(story.ticker, "AAOI")
        XCTAssertEqual(story.earliestCalls.count, 2)
        XCTAssertEqual(story.anchor.price, 53.69, accuracy: 0.001)
        XCTAssertEqual(story.peak.value, 128.96, accuracy: 0.001)
    }

    func testTradeDraftUsesMarginAndLeverageWithoutSubmitting() {
        XCTAssertEqual(OnboardingTradeDraft.sample.margin, 100)
        XCTAssertEqual(OnboardingTradeDraft.sample.leverage, 1)
        XCTAssertTrue(OnboardingTradeDraft.sample.isValid)

        let value = OnboardingTradeDraft(marginText: "125.50", leverage: 3)

        XCTAssertTrue(value.isValid)
        XCTAssertEqual(value.margin, 125.50, accuracy: 0.001)
        XCTAssertEqual(value.notional, 376.50, accuracy: 0.001)
        XCTAssertFalse(OnboardingTradeDraft(marginText: "0", leverage: 1).isValid)
        XCTAssertFalse(OnboardingTradeDraft(marginText: "100", leverage: 4).isValid)
    }
}
