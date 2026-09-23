import XCTest
@testable import BSmart

final class TradeThesisTests: XCTestCase {
    func testBodyUsesUnicodeScalarsAndKeepsOriginalMultilineText() {
        XCTAssertTrue(TradeThesis.validBody("第一行\nsecond line"))
        XCTAssertTrue(TradeThesis.validBody(String(repeating: "😀", count: 1000)))
        XCTAssertFalse(TradeThesis.validBody(String(repeating: "😀", count: 1001)))
        XCTAssertFalse(TradeThesis.validBody(" \n\t"))
        XCTAssertFalse(TradeThesis.validBody("hidden\u{0001}control"))
        XCTAssertFalse(TradeThesis.validBody("hidden\u{0085}control"))
    }

    func testThesisRequiresSameTradeAndPlausibleCountersAndTime() throws {
        let id = UUID(), now = Date()
        func thesis(_ count: Int = 1, liked: Bool = true, date: Date? = nil) -> TradeThesis {
            .init(id: id, body: "Original reasoning", publishedAt: date ?? now, likeCount: count, likedByMe: liked)
        }
        XCTAssertNoThrow(try thesis().validate(tradeID: id, executedAt: now.addingTimeInterval(-30), now: now))
        XCTAssertThrowsError(try thesis().validate(tradeID: UUID()))
        XCTAssertThrowsError(try thesis(-1).validate(tradeID: id))
        XCTAssertThrowsError(try thesis(0).validate(tradeID: id))
        XCTAssertThrowsError(try thesis(date: now.addingTimeInterval(1000)).validate(tradeID: id))
        XCTAssertThrowsError(try thesis().validate(tradeID: id, executedAt: now.addingTimeInterval(10)))
    }

    @MainActor
    func testLowerRankedSourceNeedsPublishedTheoryOrOwnPublicationEligibility() throws {
        let item = try TradeFeedDemoData.load().items[0]
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: BSmartJSONCoding.makeEncoder().encode(item)) as? [String: Any])
        var opinion = try XCTUnwrap(payload["opinion"] as? [String: Any])
        opinion["platformPercentile"] = 0.8
        payload["opinion"] = opinion
        func decode() throws -> TradeFeedItem {
            try BSmartJSONCoding.makeDecoder().decode(TradeFeedItem.self, from: JSONSerialization.data(withJSONObject: payload))
        }
        XCTAssertThrowsError(try decode().validate())
        payload["canPublishThesis"] = true
        XCTAssertNoThrow(try decode().validate())
        payload["canPublishThesis"] = false
        payload["thesis"] = ["id": item.id.uuidString, "body": "Original theory", "publishedAt": Date().ISO8601Format(),
                             "likeCount": 0, "likedByMe": false]
        XCTAssertNoThrow(try decode().validate())
    }

    @MainActor
    func testLegacyFeedDecodesAndPublishedTheoryKeepsOriginalSource() throws {
        var item = try TradeFeedDemoData.load().items[0]
        XCTAssertNil(item.thesis)
        let original = item.source
        item.thesis = .init(id: item.id, body: "My own reasoning", publishedAt: Date(), likeCount: 2, likedByMe: false)
        item.canPublishThesis = false
        item.canLikeThesis = true
        try item.validate()
        XCTAssertEqual(item.source.opinionID, original.opinionID)
        XCTAssertEqual(item.source.authorID, original.authorID)
        XCTAssertEqual(item.source.feedEventID, original.feedEventID)
        item.canPublishThesis = true
        XCTAssertThrowsError(try item.validate())
    }
}
