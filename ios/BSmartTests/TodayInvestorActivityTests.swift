import XCTest
@testable import BSmart

final class TodayInvestorActivityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testGroupsAllTickersUnderInvestorAndPreservesLatestOrdering() throws {
        let first = update("NVDA", age: 20)
        let second = update("MU", age: 40)
        let third = update("MSTR", age: 80)
        let group = try XCTUnwrap(groups([third, first, second]).first)
        XCTAssertEqual(group.id, "account:x:author")
        XCTAssertEqual(group.activities.map(\.id), [first.id, second.id, third.id])
        XCTAssertEqual(group.preview.map(\.ticker), ["NVDA", "MU"])
        XCTAssertEqual(group.name, "Same display name")
    }

    func testSourcePlatformAndIDsKeepUnrelatedPeopleSeparate() {
        let result = groups([update("NVDA"), update("MU", author: "other"),
                             update("TSLA", platform: "YouTube")], [movement("NVDA")])
        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(Set(result.map(\.id)), ["account:x:author", "account:x:other",
                                             "account:youtube:author", "money:author"])
    }

    func testCaseAndPlatformAliasesResolveSameIdentity() {
        let result = groups([update("NVDA", author: " AUTHOR ", platform: "Twitter"),
                             update("MU", platform: "X")])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.activities.count, 2)
    }

    func testDeduplicatesEventsWithoutDroppingReversalsOrDifferentMarkets() throws {
        let bullish = update("NVDA", age: 500)
        let reversed = update("NVDA", age: 100, direction: .bearish, lifecycle: .reversed)
        let money = movement("NVDA")
        let otherMarket = movement("NVDA", market: "other:NVDA")
        let result = groups([bullish, bullish, reversed], [money, money, otherMarket])
        let account = try XCTUnwrap(result.first { $0.source == .accounts })
        XCTAssertEqual(account.activities.count, 2)
        XCTAssertEqual(account.latest.direction, .bearish)
        XCTAssertEqual(result.first { $0.source == .money }?.activities.count, 2)
    }

    func testRealWindowIncludesBoundaryButNotFutureOrExpiredData() {
        let boundary = update("MU", age: 30 * 86_400)
        let result = groups([boundary, update("NVDA", age: 30 * 86_400 + 1), update("TSLA", age: -1)],
                            [movement("NVDA", age: 30 * 86_400 + 1), movement("NVDA", age: -1)])
        XCTAssertEqual(result.flatMap(\.activities).map(\.id), [boundary.id])
        XCTAssertTrue(groups([]).isEmpty)
    }

    func testNewestInvestorFirstAndStableUnderInputReordering() {
        let values = [update("NVDA", author: "a", age: 200), update("MU", author: "b", age: 100),
                      update("MSTR", author: "c", age: 100)]
        let money = movement("NVDA", age: 50)
        let result = groups(values, [money])
        XCTAssertEqual(result.map(\.id), ["money:author", "account:x:b", "account:x:c", "account:x:a"])
        XCTAssertEqual(result, groups(Array(values.reversed()), [money]))
    }

    func testSourceAndSearchIntersectWithoutHidingOtherTickerContext() throws {
        let account = try XCTUnwrap(groups([update("NVDA"), update("MU")]).first)
        XCTAssertTrue(account.matches(source: .accounts, query: " nvda "))
        XCTAssertTrue(account.matches(source: .all, query: "DISPLAY"))
        XCTAssertFalse(account.matches(source: .money, query: "NVDA"))
        XCTAssertFalse(account.matches(source: .all, query: "unknown"))
        XCTAssertEqual(account.activities.count, 2)
        let money = try XCTUnwrap(groups([], [movement("NVDA")]).first)
        XCTAssertTrue(money.matches(source: .money, query: ""))
    }

    private func groups(_ accounts: [SmartAccountUpdate], _ money: [SmartMoneyMovement] = []) -> [TodayInvestorActivity] {
        TodayInvestorActivity.groups(accountUpdates: accounts, moneyMovements: money, now: now)
    }

    private func update(_ ticker: String, author: String = "author", age: TimeInterval = 100,
                        platform: String = "X", direction: SignalDirection = .bullish,
                        lifecycle: SmartAccountLifecycle = .new) -> SmartAccountUpdate {
        SmartAccountUpdate(id: UUID(), ticker: ticker, companyName: ticker, authorId: author,
                           authorName: "Same display name", platform: platform, score: 120, platformPercentile: 0.1,
                           direction: direction, lifecycle: lifecycle, horizon: "20D", targetPrice: nil,
                           thesis: "Source thesis", invalidation: nil, publishedAt: now.addingTimeInterval(-age), evidenceURL: nil)
    }

    private func movement(_ ticker: String, age: TimeInterval = 100, market: String = "xyz:NVDA") -> SmartMoneyMovement {
        SmartMoneyMovement(id: UUID(), ticker: ticker, companyName: ticker, accountId: "author", accountLabel: "author",
                           accountScore: 80, market: market, action: .reduced, direction: .bullish,
                           notionalBefore: 1000, notionalAfter: 800, notionalChange: -200, leverage: nil,
                           observedAt: now.addingTimeInterval(-age), evidenceURL: nil)
    }
}
