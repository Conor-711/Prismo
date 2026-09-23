import XCTest
@testable import BSmart

@MainActor
final class PopularOpinionsTests: XCTestCase {
    func testDemoAggregatesDistinctPeopleUsingTheirLatestDirection() throws {
        let demo = try TradeFeedDemoData.load()
        let first = demo.items[0], other = demo.items[1]
        let now = Date()
        let duplicate = TradeFeedItem(id: UUID(), trader: first.trader, opinion: first.opinion,
            side: .short, notionalUSD: "15", marketCoin: first.marketCoin, executedAt: now.addingTimeInterval(-5))
        let secondPerson = TradeFeedItem(id: UUID(), trader: other.trader, opinion: first.opinion,
            side: .long, notionalUSD: "20", marketCoin: first.marketCoin, executedAt: now.addingTimeInterval(-10))
        let expired = TradeFeedItem(id: UUID(), trader: demo.items[2].trader, opinion: first.opinion,
            side: .long, notionalUSD: "30", marketCoin: first.marketCoin, executedAt: now.addingTimeInterval(-8 * 86400))
        let page = try TradeFeedDemoData(items: demo.items + [duplicate, secondPerson, expired]).popular(offset: 0, now: now)
        try page.validate(offset: 0)
        XCTAssertEqual(page.items[0].id, first.opinion.id)
        XCTAssertEqual(page.items[0].totalTraders, 2)
        XCTAssertEqual(page.items[0].longTraders, 1)
        XCTAssertEqual(page.items[0].shortTraders, 1)
    }

    func testPageRejectsWrongTotalsRankingAndBrokenPagination() throws {
        let rows = try TradeFeedDemoData.load().popular(offset: 0).items
        let large = PopularOpinion(opinion: rows[1].opinion, totalTraders: 10, longTraders: 7, shortTraders: 3)
        XCTAssertThrowsError(try PopularOpinionsPage(items: [rows[0], large], nextOffset: nil, windowDays: 7).validate(offset: 0))
        XCTAssertThrowsError(try PopularOpinionsPage(items: rows, nextOffset: nil, windowDays: 30).validate(offset: 0))
        XCTAssertThrowsError(try PopularOpinion(opinion: rows[0].opinion, totalTraders: 10,
            longTraders: 7, shortTraders: 4).validate())
        XCTAssertThrowsError(try PopularOpinionsPage(items: [], nextOffset: 0, windowDays: 7).validate(offset: 0))
    }

    func testRefreshFailureAndAccountExitCannotRetainStaleRecords() async throws {
        let page = try TradeFeedDemoData.load().popular(offset: 0)
        let store = PopularOpinionsStore()
        await store.load(reset: true) { _ in page }
        XCTAssertFalse(store.items.isEmpty)
        await store.load(reset: true) { _ in throw BSmartAPIError.httpStatus(503) }
        XCTAssertTrue(store.items.isEmpty); XCTAssertTrue(store.failed)
        await store.load(reset: true) { _ in store.clear(); return page }
        XCTAssertTrue(store.items.isEmpty); XCTAssertFalse(store.hasLoaded)
    }
}
