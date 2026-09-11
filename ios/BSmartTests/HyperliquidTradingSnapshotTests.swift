import XCTest
@testable import BSmart

final class HyperliquidTradingSnapshotTests: XCTestCase {
    private typealias F = HyperliquidTradingFixture

    func testSideSpecificCapacityUsesExactValuesNotTheWithdrawableBalance() throws {
        let snapshot = try F.snapshot()
        XCTAssertNoThrow(try check(snapshot, F.order(size: "8.123")))
        XCTAssertNoThrow(try check(snapshot, F.order(side: .sell, size: "3.125")))
        for order in [try F.order(size: "8.124"), try F.order(side: .sell, size: "3.126")] {
            XCTAssertThrowsError(try check(snapshot, order)) {
                XCTAssertEqual($0 as? HyperliquidTradingCheckError, .exceedsCapacity)
            }
        }
    }

    func testZeroOpeningCapacityStillPermitsCorrectReduceOnlyClose() throws {
        for (quantity, side): (String, HyperliquidOrderIntent.Side) in [("-2.5", .buy), ("2.5", .sell)] {
            let snapshot = try F.snapshot(active: F.active(buy: "0", sell: "0"),
                                          positions: F.positions(rows: [F.row(size: quantity)]))
            XCTAssertNoThrow(try check(snapshot, F.order(side: side, size: "2.5", reduceOnly: true)))
            XCTAssertNoThrow(try check(snapshot, F.order(side: side, size: "0.001", reduceOnly: true)))
            XCTAssertThrowsError(try check(snapshot, F.order(side: side)))
            for order in [try F.order(side: side, size: "2.501", reduceOnly: true),
                          try F.order(side: side == .buy ? .sell : .buy, reduceOnly: true)] {
                XCTAssertThrowsError(try check(snapshot, order)) {
                    XCTAssertEqual($0 as? HyperliquidTradingCheckError, .invalidReduction)
                }
            }
        }
        XCTAssertThrowsError(try check(F.snapshot(), F.order(reduceOnly: true)))
    }

    func testReviewedLeverageCannotBeSilentlyReplaced() throws {
        let snapshot = try F.snapshot(), order = try F.order()
        for (value, mode): (Int, HyperliquidMarketLeverage.Mode) in [(20, .cross), (10, .isolated)] {
            XCTAssertThrowsError(try snapshot.checkConstraints(order: order, wallet: F.wallet,
                reviewedLeverage: value, reviewedMarginMode: mode, now: F.now, continuousNow: F.instant)) {
                XCTAssertEqual($0 as? HyperliquidTradingCheckError, .leverageChanged)
            }
        }
    }

    func testSnapshotBoundToExactWalletAndMarketWithOptionalInternalBackup() throws {
        let snapshot = try F.snapshot()
        for wallet in [DeviceWalletSummary(accountID: UUID(), address: F.wallet.address, recoveryVerified: true),
                       .init(accountID: F.wallet.accountID, address: "0x" + String(repeating: "1", count: 40), recoveryVerified: true)] {
            XCTAssertThrowsError(try snapshot.validate(wallet: wallet, now: F.now, continuousNow: F.instant))
            if wallet.recoveryVerified { XCTAssertThrowsError(try check(snapshot, F.order(wallet: wallet))) }
        }
        let unbacked = DeviceWalletSummary(accountID: F.wallet.accountID, address: F.wallet.address, recoveryVerified: false)
        XCTAssertNoThrow(try snapshot.validate(wallet: unbacked, now: F.now, continuousNow: F.instant))
        XCTAssertThrowsError(try check(snapshot, F.order(market: HyperliquidOrderTestSupport.market())))
    }

    func testBothClocksAndServerTimeBoundLifetime() throws {
        let snapshot = try F.snapshot()
        for (wall, steady): (Double, Duration) in [(-0.001, .zero), (15, .zero), (0, .seconds(15)), (0, .seconds(-1))] {
            XCTAssertThrowsError(try snapshot.validate(wallet: F.wallet, now: F.now.addingTimeInterval(wall),
                                                      continuousNow: F.instant.advanced(by: steady)))
        }
        let older = try F.snapshot(positions: F.positions(at: F.now.addingTimeInterval(-14)))
        XCTAssertEqual(older.expiresAt, F.now.addingTimeInterval(1))
        XCTAssertNoThrow(try older.validate(wallet: F.wallet, now: F.now.addingTimeInterval(0.999),
                                           continuousNow: F.instant.advanced(by: .milliseconds(999))))
        XCTAssertThrowsError(try older.validate(wallet: F.wallet, now: older.expiresAt,
                                                continuousNow: F.instant.advanced(by: .seconds(1))))
        // A frozen/adjusted wall clock cannot extend the server's one remaining second.
        XCTAssertThrowsError(try older.validate(wallet: F.wallet, now: F.now,
                                                continuousNow: F.instant.advanced(by: .seconds(1))))
        let ahead = try F.snapshot(positions: F.positions(at: F.now.addingTimeInterval(2)))
        XCTAssertEqual(ahead.expiresAt, F.now.addingTimeInterval(15))
    }

    func testExpiredAndFutureDatedOrdersAreRejected() throws {
        let snapshot = try F.snapshot()
        let nowMS = UInt64(F.now.timeIntervalSince1970 * 1000)
        for order in [try F.order(nonce: nowMS - 30_000, expiry: nowMS),
                      try F.order(nonce: nowMS + 1_001, expiry: nowMS + 10_000)] {
            XCTAssertThrowsError(try check(snapshot, order)) {
                XCTAssertEqual($0 as? HyperliquidTradingCheckError, .stale)
            }
        }
    }

    private func check(_ snapshot: HyperliquidTradingSnapshot, _ order: HyperliquidOrderIntent) throws {
        try snapshot.checkConstraints(order: order, wallet: F.wallet, reviewedLeverage: 10,
                                      reviewedMarginMode: .cross, now: F.now, continuousNow: F.instant)
    }
}
