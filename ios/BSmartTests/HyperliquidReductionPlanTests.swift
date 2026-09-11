import XCTest
@testable import BSmart

final class HyperliquidReductionPlanTests: XCTestCase {
    typealias F = HyperliquidTradingFixture
    typealias Q = HyperliquidQuoteFixture

    func testLongClosesWithSellAndShortWithBuy() throws {
        for (position, side) in [("2.503", HyperliquidOrderIntent.Side.sell), ("-2.503", .buy)] {
            let order = try reduction(position: position)
            XCTAssertEqual(order.side, side)
            XCTAssertEqual(order.size.wire, "2.503")
            XCTAssertTrue(order.reduceOnly)
            XCTAssertNil(order.builderFee)
            XCTAssertEqual(order.expiresAfter - order.nonce, 60_000)
        }
    }

    func testPartialReductionAlwaysRoundsDown() throws {
        for (percent, size) in [(25, "0.625"), (50, "1.251"), (75, "1.877"), (100, "2.503")] {
            XCTAssertEqual(try reduction(position: "2.503", percent: percent).size.wire, size)
        }
    }

    func testDustCloseDoesNotRoundUpToOpeningMinimum() throws {
        XCTAssertEqual(try reduction(position: "0.001").size.wire, "0.001")
        XCTAssertThrowsError(try reduction(position: "0.001", percent: 25)) { error in
            guard case HyperliquidLiveOrderError.invalidReduction = error else { return XCTFail("\(error)") }
        }
    }

    func testNoPositionCannotBecomeAnOpeningOrder() throws {
        for size in [nil, "0"] as [String?] {
            XCTAssertThrowsError(try reduction(position: size)) { error in
                guard case HyperliquidLiveOrderError.noPosition = error else { return XCTFail("\(error)") }
            }
        }
    }

    func testInvalidPercentSlippageAndNonceFail() throws {
        for percent in [-1, 0, 101, Int.max] { XCTAssertThrowsError(try reduction(percent: percent)) }
        for slippage in [0, 9, 101, UInt64.max] { XCTAssertThrowsError(try reduction(slippage: slippage)) }
        for nonce in [0, 9_007_199_254_740_991, UInt64.max] { XCTAssertThrowsError(try reduction(nonce: nonce)) }
    }

    func testSideSpecificPriceLimitDoesNotExceedSelectedSlippage() throws {
        XCTAssertEqual(try reduction(position: "-2.5").limitPrice.wire, "221.1")
        XCTAssertEqual(try reduction(position: "2.5").limitPrice.wire, "217.91")
    }

    func testDifferentMarketBookIsRejected() throws {
        let snapshot = try snapshot(position: "2.5")
        let market = try Q.market(scale: "0", growth: nil, native: true)
        let book = try HyperliquidOrderBook.decode(Q.book(coin: "NVDA"), market: market, now: F.now)
        XCTAssertThrowsError(try HyperliquidMarketOrderPlan.reduction(percent: 100, slippageBPS: 50,
            wallet: F.wallet, snapshot: snapshot, book: book, nonce: 1_789_084_801_000))
    }

    func testDecodedSpotMarketCannotEnterOrderIntent() throws {
        for (asset, dex, coin) in [(10_000, "", "PURR/USDC"), (10_000, "", "BTC"),
                                  (100_000, "xyz", F.coin), (110_000, "spot", "spot:NVDA"),
                                  (0, "", "@0"), (0, "", "+123"), (0, "xyz", F.coin)] {
            var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(Q.market())) as? [String: Any])
            fields["asset"] = asset; fields["dex"] = dex; fields["coin"] = coin
            let market = try JSONDecoder().decode(HyperliquidExecutionMarket.self, from: F.data(fields))
            XCTAssertThrowsError(try F.order(market: market), "\(dex) \(asset) \(coin)")
        }
    }

    func testValidNativeAndBuilderPerpetualsStillCreateOrders() throws {
        XCTAssertNoThrow(try F.order(market: Q.market(scale: "0", growth: nil, native: true)))
        XCTAssertNoThrow(try F.order(market: Q.market()))
    }

    private func snapshot(position: String?) throws -> HyperliquidTradingSnapshot {
        let market = try Q.market()
        return try .init(accountID: F.wallet.accountID, owner: F.wallet.address, market: market, mode: .unifiedAccount,
            active: .decode(F.active(), owner: F.wallet.address, market: market),
            positions: .decode(F.positions(rows: position.map { [F.row(size: $0)] } ?? []), market: market, now: F.now),
            requestedAt: F.now, checkedAt: F.now, requestedContinuousAt: F.instant, checkedContinuousAt: F.instant)
    }

    private func reduction(position: String? = "-2.5", percent: Int = 100, slippage: UInt64 = 50,
                           nonce: UInt64 = 1_789_084_801_000) throws -> HyperliquidOrderIntent {
        let snapshot = try snapshot(position: position)
        let book = try HyperliquidOrderBook.decode(Q.book(), market: snapshot.market, now: F.now)
        return try HyperliquidMarketOrderPlan.reduction(percent: percent, slippageBPS: slippage, wallet: F.wallet,
                                                       snapshot: snapshot, book: book, nonce: nonce)
    }
}
