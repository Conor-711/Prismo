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
}
