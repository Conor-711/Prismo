import XCTest
@testable import BSmart

final class HyperliquidOrderDecimalTests: XCTestCase {
    func testCanonicalAmountsWithoutFloatingPointRounding() throws {
        XCTAssertEqual(try HyperliquidOrderDecimal("230.9000").wire, "230.9")
        XCTAssertEqual(try HyperliquidOrderDecimal("0.000").wire, "0")
        XCTAssertEqual(try HyperliquidOrderDecimal("9007199254740993.123456789123456789").wire,
                       "9007199254740993.123456789123456789")
        XCTAssertEqual(try HyperliquidOrderDecimal("3.100"), try HyperliquidOrderDecimal("3.1"))
        XCTAssertLessThan(try HyperliquidOrderDecimal("9.999999999999999999"), try HyperliquidOrderDecimal("10"))
    }

    func testMalformedAmountsAreRejected() {
        for text in ["", " ", " 1", "1 ", "1e2", "+1", "-1", "NaN", "inf", "01", ".1", "1.",
                     "1.2.3", "1,000", "１", "1\n", "0.0000000000000000001", String(repeating: "9", count: 79)] {
            XCTAssertThrowsError(try HyperliquidOrderDecimal(text), text)
        }
    }

    func testOfficialPerpPricePrecisionExamples() throws {
        for (price, decimals) in [("1234.5", 0), ("0.001234", 0), ("0.01234", 1), ("123456", 6)] {
            XCTAssertNoThrow(try HyperliquidOrderDecimal(price).validatePrice(sizeDecimals: decimals), price)
        }
        for (price, decimals) in [("1234.56", 0), ("0.0012345", 0), ("0.012345", 1), ("1.1", 6), ("0", 0)] {
            XCTAssertThrowsError(try HyperliquidOrderDecimal(price).validatePrice(sizeDecimals: decimals), price)
        }
    }

    func testSizePrecisionIsNeverSilentlyRounded() throws {
        XCTAssertNoThrow(try HyperliquidOrderDecimal("1.00100").validateSize(decimals: 3))
        XCTAssertThrowsError(try HyperliquidOrderDecimal("1.0001").validateSize(decimals: 3))
        for decimals in [-1, 7, Int.max] {
            XCTAssertThrowsError(try HyperliquidOrderDecimal("1").validateSize(decimals: decimals))
        }
        XCTAssertThrowsError(try HyperliquidOrderDecimal("0").validateSize(decimals: 3))
    }

    func testInvalidIntentCannotReachEncoding() throws {
        XCTAssertThrowsError(try HyperliquidOrderTestSupport.order(size: "1.0001"))
        for cloid in ["0x", "0x" + String(repeating: "0", count: 32), "0x" + String(repeating: "A", count: 32)] {
            XCTAssertThrowsError(try HyperliquidOrderTestSupport.order(cloid: cloid))
        }
        let timestamps: [(UInt64, UInt64)] = [(0, 100), (100, 100), (100, 99), (100, 60101),
            (9_007_199_254_740_990, 9_007_199_254_740_992), (.max, .max)]
        for (nonce, expiry) in timestamps {
            XCTAssertThrowsError(try HyperliquidOrderTestSupport.order(nonce: nonce, expiresAfter: expiry))
        }
        for owner in ["0x" + String(repeating: "0", count: 40), HyperliquidOrderTestSupport.wallet.address.uppercased()] {
            let wallet = DeviceWalletSummary(accountID: UUID(), address: owner, recoveryVerified: true)
            XCTAssertThrowsError(try HyperliquidOrderIntent(wallet: wallet, market: HyperliquidOrderTestSupport.market(),
                side: .buy, size: "1", limitPrice: "230.9", reduceOnly: false,
                cloid: "0x00000000000000000000000000000001", nonce: 1000, expiresAfter: 31000))
        }
    }

    func testInternalWalletWithoutBackupAndRandomCloid() throws {
        let wallet = DeviceWalletSummary(accountID: UUID(), address: HyperliquidOrderTestSupport.wallet.address,
                                        recoveryVerified: false)
        XCTAssertNoThrow(try HyperliquidOrderIntent(wallet: wallet, market: HyperliquidOrderTestSupport.market(),
            side: .buy, size: "1", limitPrice: "230.9", reduceOnly: false,
            cloid: "0x00000000000000000000000000000001", nonce: 1000, expiresAfter: 31000))
        XCTAssertFalse(wallet.recoveryVerified)
        let identifiers = try (0..<100).map { _ in try HyperliquidOrderIntent.randomCloid() }
        XCTAssertEqual(Set(identifiers).count, 100)
        XCTAssertTrue(identifiers.allSatisfy { $0.count == 34 && FundingHex.decode($0)?.count == 16 })
    }
}
