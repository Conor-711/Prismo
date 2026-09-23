import XCTest
@testable import BSmart

final class OpinionTradersTests: XCTestCase {
    func testSourceCannotAttachToAnotherTicker() {
        let source = OpinionTradeSource(opinionID: UUID(), ticker: "NVDA")
        XCTAssertTrue(source.matches(symbol: "nvda"))
        XCTAssertFalse(source.matches(symbol: "MU"))
    }

    func testPageValidatesCountsAndProgress() throws {
        let trader = OpinionTrader(id: UUID(), nickname: "Casey", avatarURL: nil, side: .long, tradedAt: .now)
        try OpinionTradersPage(totalTraders: 3, publicTraders: 2, traders: [trader], nextOffset: 1).validate(offset: 0)
        XCTAssertThrowsError(try OpinionTradersPage(totalTraders: 0, publicTraders: 2, traders: [trader], nextOffset: nil).validate(offset: 0))
        XCTAssertThrowsError(try OpinionTradersPage(totalTraders: 2, publicTraders: 2, traders: [trader, trader], nextOffset: nil).validate(offset: 0))
        XCTAssertThrowsError(try OpinionTradersPage(totalTraders: 3, publicTraders: 2, traders: [], nextOffset: 0).validate(offset: 0))
    }

    func testNonLiveClientCannotInventZeroTraders() async {
        do {
            _ = try await BundleBSmartAPIClient().fetchOpinionTraders(opinionID: UUID(), offset: 0)
            XCTFail("Bundled historical data cannot prove real trading activity")
        } catch BSmartAPIError.tradeStatisticsUnavailable { } catch { XCTFail("Unexpected error: \(error)") }
    }

    func testDirectionTotalsIncludePrivatePeopleAndRejectInconsistentCounts() throws {
        let page = OpinionTradersPage(totalTraders: 10, publicTraders: 0, traders: [], nextOffset: nil,
                                      longTraders: 7, shortTraders: 3)
        try page.validate(offset: 0)
        let decoded = try JSONDecoder().decode(OpinionTradersPage.self, from: JSONEncoder().encode(page))
        XCTAssertEqual(decoded.longTraders, 7); XCTAssertEqual(decoded.shortTraders, 3)
        for counts in [(7, 4), (-1, 11), (7, nil), (nil, 3)] as [(Int?, Int?)] {
            XCTAssertThrowsError(try OpinionTradersPage(totalTraders: 10, publicTraders: 0,
                traders: [], nextOffset: nil, longTraders: counts.0, shortTraders: counts.1).validate(offset: 0))
        }
        try OpinionTradersPage(totalTraders: 0, publicTraders: 0, traders: [], nextOffset: nil,
                               longTraders: 0, shortTraders: 0).validate(offset: 0)
    }

    func testVerifiedTradeValueDecodesExactlyAndRejectsInvalidAmounts() throws {
        let page = OpinionTradersPage(totalTraders: 2, publicTraders: 0, traders: [], nextOffset: nil,
                                      longTraders: 2, shortTraders: 0, totalNotionalUSD: "364.75")
        try page.validate(offset: 0)
        XCTAssertEqual(page.totalNotionalLabel, "$364.75")
        let decoded = try JSONDecoder().decode(OpinionTradersPage.self, from: JSONEncoder().encode(page))
        XCTAssertEqual(decoded.totalNotionalUSD, "364.75")
        for raw in ["-1", "1e3", "abc", "", String(repeating: "9", count: 65)] {
            XCTAssertThrowsError(try OpinionTradersPage(totalTraders: 0, publicTraders: 0,
                traders: [], nextOffset: nil, totalNotionalUSD: raw).validate(offset: 0))
        }
    }

    func testDefaultExpansionRequiresNonzeroTradeActivity() {
        let empty = OpinionTradersPage(totalTraders: 0, publicTraders: 0, traders: [], nextOffset: nil,
                                       longTraders: 0, shortTraders: 0, totalNotionalUSD: "0.00")
        XCTAssertFalse(empty.hasTradeActivity)
        XCTAssertTrue(OpinionTradersPage(totalTraders: 1, publicTraders: 0, traders: [], nextOffset: nil,
                                         totalNotionalUSD: "0").hasTradeActivity)
        XCTAssertTrue(OpinionTradersPage(totalTraders: 0, publicTraders: 0, traders: [], nextOffset: nil,
                                         totalNotionalUSD: "0.01").hasTradeActivity)
    }
}
