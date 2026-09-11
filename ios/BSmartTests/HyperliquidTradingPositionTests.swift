import XCTest
@testable import BSmart

final class HyperliquidTradingPositionTests: XCTestCase {
    private typealias F = HyperliquidTradingFixture

    func testSignedTargetAndEmptyPositionKeepServerTime() throws {
        let value = try decode(F.positions(rows: [F.row(), F.row(coin: "xyz:TSLA")]))
        XCTAssertEqual(value.position?.quantity.magnitude.wire, "2.5")
        XCTAssertEqual(value.position?.quantity.isNegative, true)
        XCTAssertEqual(value.updatedAt, F.now)
        XCTAssertNil(try decode(F.positions()).position)
        XCTAssertNil(try decode(F.positions(rows: [F.row(size: "-0.0")])).position)
        let isolated = try decode(F.positions(rows: [F.row(size: "0.033", leverage: F.leverage("isolated"))]))
        XCTAssertEqual(isolated.position?.quantity.isNegative, false)
        XCTAssertEqual(isolated.position?.leverage.isolatedRawUSD?.isNegative, true)
    }

    func testNativePositionRequiresNativeNamespace() throws {
        let market = try HyperliquidOrderTestSupport.market(asset: 0)
        let valid = try F.positions(rows: [F.row(coin: "ASSET0")])
        XCTAssertNotNil(try HyperliquidTradingPositionState.decode(valid, market: market, now: F.now).position)
        XCTAssertThrowsError(try HyperliquidTradingPositionState.decode(F.positions(rows: [F.row()]), market: market, now: F.now))
    }

    func testPositionSchemaNamespaceDuplicationPrecisionAndLeverageFailClosed() throws {
        var unsupported = F.row(); unsupported["type"] = "twoWay"
        for rows in [[F.row(), F.row()], [F.row(coin: "other:NVDA")], [F.row(coin: "NVDA")],
                     [F.row(coin: "xyz:")], [F.row(coin: "xyz:one:two")], [unsupported],
                     [F.row(size: "0.0001")], [F.row(size: "-0.0001")], [F.row(size: "1e3")],
                     [F.row(leverage: F.leverage("cross", 21))]] {
            XCTAssertThrowsError(try decode(F.positions(rows: rows)))
        }
        for data in [try F.data(["assetPositions": []]), try F.data(["time": 0, "assetPositions": []]),
                     try F.data(["time": 9_007_199_254_740_992, "assetPositions": []]),
                     try F.data(["time": true, "assetPositions": []]), Data("null".utf8),
                     try F.positions(rows: Array(repeating: F.row(), count: 10_001)),
                     Data(repeating: 32, count: 1_048_577)] {
            XCTAssertThrowsError(try decode(data))
        }
    }

    func testEmptyPositionDoesNotBypassFreshnessAndRevalidation() throws {
        for offset in [-15.0, -100, 2.001] {
            XCTAssertThrowsError(try decode(F.positions(at: F.now.addingTimeInterval(offset)))) {
                XCTAssertEqual($0 as? HyperliquidTradingCheckError, .stale)
            }
        }
        let value = try decode(F.positions(at: F.now.addingTimeInterval(-14)))
        XCTAssertNoThrow(try value.validate(now: F.now.addingTimeInterval(0.999)))
        XCTAssertThrowsError(try value.validate(now: F.now.addingTimeInterval(1)))
        XCTAssertNoThrow(try decode(F.positions(at: F.now.addingTimeInterval(2))))
        XCTAssertThrowsError(try value.validate(now: Date(timeIntervalSince1970: .nan)))
    }

    private func decode(_ data: Data) throws -> HyperliquidTradingPositionState {
        try .decode(data, market: F.market(), now: F.now)
    }
}
