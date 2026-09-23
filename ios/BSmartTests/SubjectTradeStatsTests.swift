import XCTest
@testable import BSmart

@MainActor
final class SubjectTradeStatsTests: XCTestCase {
    private let subject = TradeSubject(kind: .account, id: "test-author", platform: "X")
    private var example: SubjectTradeStats {
        .init(kind: .account, subjectId: "test-author", platform: "X",
              totalTrades: 10, longTrades: 7, shortTrades: 3, sourceCount: 10)
    }

    func testFixtureAllowsSameUserAcrossTenSourcesAndValidatesDirectionTotals() throws {
        let result = try BSmartJSONCoding.makeDecoder().decode(SubjectTradeStats.self, from: Data("""
        {"kind":"account","subjectId":"test-author","platform":"X",
         "totalTrades":10,"longTrades":7,"shortTrades":3,"sourceCount":10}
        """.utf8))
        try result.validate(subject: subject)
        XCTAssertEqual(result, example)
        XCTAssertThrowsError(try SubjectTradeStats(kind: .account, subjectId: subject.id, platform: "X",
            totalTrades: 10, longTrades: 7, shortTrades: 4, sourceCount: 10).validate(subject: subject))
        XCTAssertThrowsError(try SubjectTradeStats(kind: .account, subjectId: subject.id, platform: "X",
            totalTrades: 10, longTrades: 7, shortTrades: 3, sourceCount: 0).validate(subject: subject))
        XCTAssertThrowsError(try SubjectTradeStats(kind: .account, subjectId: subject.id, platform: "X",
            totalTrades: -1, longTrades: 0, shortTrades: -1, sourceCount: 0).validate(subject: subject))
    }

    func testRejectsDifferentAuthorPlatformAndSourceKind() {
        for other in [TradeSubject(kind: .account, id: "other", platform: "X"),
                      .init(kind: .account, id: subject.id, platform: "YouTube"),
                      .init(kind: .money, id: subject.id, platform: "hyperliquid")] {
            XCTAssertThrowsError(try example.validate(subject: other))
        }
    }

    func testZeroIsValidButFailureDoesNotBecomeZero() async throws {
        let zero = SubjectTradeStats(kind: .account, subjectId: subject.id, platform: "X",
            totalTrades: 0, longTrades: 0, shortTrades: 0, sourceCount: 0)
        let store = SubjectTradeStatsStore()
        await store.load(subject: subject) { zero }
        XCTAssertEqual(store.stats?.totalTrades, 0)
        await store.load(subject: subject) { throw BSmartAPIError.httpStatus(503) }
        XCTAssertNil(store.stats); XCTAssertTrue(store.failed)
    }

    func testAccountExitInvalidatesPendingResult() async {
        let store = SubjectTradeStatsStore()
        await store.load(subject: subject) { store.clear(); return example }
        XCTAssertNil(store.stats); XCTAssertFalse(store.failed); XCTAssertFalse(store.loading)
    }
}
