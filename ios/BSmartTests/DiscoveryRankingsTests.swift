import XCTest
@testable import BSmart

@MainActor
final class DiscoveryRankingsTests: XCTestCase {
    func testBothRankingsSupportEverySortWindowAndThreeItemPreview() throws {
        let now = Date(), demo = try TradeFeedDemoData.load(now: Date().addingTimeInterval(-1))
        for kind in DiscoveryRankingKind.allCases {
            for sort in DiscoveryRankingSort.allCases {
                for window in DiscoveryRankingWindow.allCases {
                    let query = DiscoveryRankingQuery(kind: kind, sort: sort, window: window)
                    let page = try demo.rankings(query: query, offset: 0, limit: 3, asOf: now)
                    try page.validate(query: query, offset: 0, limit: 3, anchor: now)
                    XCTAssertLessThanOrEqual(page.items.count,3)
                    XCTAssertFalse(page.items.isEmpty)
                    if let next = page.nextOffset {
                        let second = try demo.rankings(query: query, offset: next, limit: 3, asOf: page.asOf)
                        try second.validate(query: query, offset: next, limit: 3, anchor: page.asOf)
                        XCTAssertTrue(Set(page.items.map(\.id)).isDisjoint(with: Set(second.items.map(\.id))))
                    }
                }
            }
        }
    }

    func testRepeatedTradesIncreaseVolumeButNotPeople() throws {
        let demo = try TradeFeedDemoData.load(), first = demo.items[0], now = Date()
        let repeatOrder = TradeFeedItem(id: UUID(), trader: first.trader, opinion: first.opinion,
            side: .short, notionalUSD: "0.2", marketCoin: first.marketCoin, executedAt: now.addingTimeInterval(-1))
        let source = TradeFeedItem(id: UUID(), trader: first.trader, opinion: first.opinion,
            side: .long, notionalUSD: "0.1", marketCoin: first.marketCoin, executedAt: now.addingTimeInterval(-2))
        let query = DiscoveryRankingQuery(kind: .investors, sort: .volume)
        let page = try TradeFeedDemoData(items: [source, repeatOrder]).rankings(query: query, offset: 0, limit: 3, asOf: now)
        try page.validate(query: query, offset: 0, limit: 3)
        XCTAssertEqual(page.items[0].totalTraders,1)
        XCTAssertEqual(page.items[0].shortTraders,1)
        XCTAssertEqual(page.items[0].volume,Decimal(string: "0.3"))
    }

    func testRejectsMismatchedFiltersAndStaleResponses() async throws {
        let demo = try TradeFeedDemoData.load(), query = DiscoveryRankingQuery(kind: .opinions)
        let page = try demo.rankings(query: query, offset: 0, limit: 3)
        XCTAssertThrowsError(try page.validate(query: .init(kind: .investors), offset: 0, limit: 3))
        XCTAssertThrowsError(try page.validate(query: query, offset: 0, limit: 2))
        let store = DiscoveryRankingsStore()
        await store.load(query: query, limit: 3, reset: true) { _, _ in page }
        XCTAssertFalse(store.items.isEmpty)
        await store.load(query: query, limit: 3, reset: true) { _, _ in throw BSmartAPIError.httpStatus(503) }
        XCTAssertTrue(store.failed); XCTAssertTrue(store.items.isEmpty)
        await store.load(query: query, limit: 3, reset: true) { _, _ in store.clear(); return page }
        XCTAssertFalse(store.hasLoaded); XCTAssertTrue(store.items.isEmpty)
    }
}
