import XCTest
@testable import BSmart

final class HyperliquidActiveTradingDataTests: XCTestCase {
    private typealias F = HyperliquidTradingFixture

    func testSideCapacityRetainsExchangeOrderAndExactDecimals() throws {
        let value = try decode(F.active())
        XCTAssertEqual(value.buy.maximumSize.wire, "8.123456789012345678")
        XCTAssertEqual(value.sell.maximumSize.wire, "3.125")
        XCTAssertEqual(value.buy.availableToTrade.wire, "180.001234567890123456")
        XCTAssertEqual(value.markPrice.wire, "219.88")
        XCTAssertEqual(value.leverage.multiplier, 10)
        XCTAssertNil(value.leverage.isolatedRawUSD)
        // Arrays are directional, never sorted as a minimum/maximum range.
        let other = try decode(F.active(buy: "0", sell: "8"))
        XCTAssertEqual(other.buy.maximumSize.wire, "0")
        XCTAssertEqual(other.sell.maximumSize.wire, "8")
    }

    func testNegativeIsolatedRawUSDAndNegativeZeroAreValid() throws {
        let value = try decode(F.active(leverage: F.leverage("isolated")))
        XCTAssertEqual(value.leverage.mode, .isolated)
        XCTAssertEqual(value.leverage.isolatedRawUSD?.magnitude.wire, "95.059824")
        XCTAssertEqual(value.leverage.isolatedRawUSD?.isNegative, true)
        XCTAssertFalse(try HyperliquidSignedDecimal("-0.0").isNegative)
    }

    func testRejectsMalformedOrForeignAccountData() throws {
        for changes: [String: Any] in [
            ["user": "0x" + String(repeating: "1", count: 40)], ["coin": "NVDA"], ["coin": "xyz:nvda"],
            ["maxTradeSzs": ["1"]], ["maxTradeSzs": ["1", "2", "3"]], ["availableToTrade": []],
            ["availableToTrade": [1, 2]], ["markPx": "0"], ["markPx": 1], ["markPx": "NaN"],
            ["maxTradeSzs": ["-1", "2"]], ["maxTradeSzs": ["1e2", "2"]],
            ["availableToTrade": ["1", "-1"]], ["leverage": NSNull()]
        ] { XCTAssertThrowsError(try decode(F.active(overrides: changes))) }
        for data in [Data("null".utf8), Data("{}".utf8), Data(repeating: 32, count: 65_537)] {
            XCTAssertThrowsError(try decode(data))
        }
    }

    func testRejectsUnknownInvalidAndInconsistentLeverage() throws {
        for leverage: [String: Any] in [
            F.leverage("cross", 0), F.leverage("cross", 21), F.leverage("future", 10),
            ["type": "cross", "value": true], ["type": "cross", "value": 1.5],
            ["type": "cross", "value": 10, "rawUsd": "1"], ["type": "isolated", "value": 10],
            F.leverage("isolated", 10, raw: "--1"), F.leverage("isolated", 10, raw: "-NaN")
        ] { XCTAssertThrowsError(try decode(F.active(leverage: leverage))) }
        XCTAssertThrowsError(try HyperliquidActiveTradingData.decode(F.active(), owner: F.wallet.address,
                                                                    market: F.market(mode: "noCross")))
        XCTAssertNoThrow(try HyperliquidActiveTradingData.decode(F.active(leverage: F.leverage("isolated")),
            owner: F.wallet.address, market: F.market(mode: "strictIsolated")))
    }

    private func decode(_ data: Data) throws -> HyperliquidActiveTradingData {
        try .decode(data, owner: F.wallet.address, market: F.market())
    }
}
