import XCTest
@testable import BSmart

final class ArbitrumDepositPolicyTests: XCTestCase {
    func testExactUSDCAmountsWithoutLegacyBridgeMinimum() throws {
        XCTAssertEqual(try ArbitrumDepositPolicy.units("5"), 5_000_000)
        XCTAssertEqual(try ArbitrumDepositPolicy.units("12.345678"), 12_345_678)
        XCTAssertEqual(try ArbitrumDepositPolicy.units("0.000001"), 1)
        XCTAssertEqual(try ArbitrumDepositPolicy.validate(amount: "5", chainID: 42161,
                                                       tokenAddress: ArbitrumDepositPolicy.nativeUSDC), 5_000_000)
        XCTAssertEqual(try ArbitrumDepositPolicy.validate(amount: "4.999999", chainID: 42161,
            tokenAddress: ArbitrumDepositPolicy.nativeUSDC), 4_999_999)
        XCTAssertEqual(try ArbitrumDepositPolicy.validate(amount: "10000000", chainID: 42161,
            tokenAddress: ArbitrumDepositPolicy.nativeUSDC), 10_000_000_000_000)
        for amount in ["0", "10000000.000001"] {
            XCTAssertThrowsError(try ArbitrumDepositPolicy.validate(amount: amount, chainID: 42161,
                tokenAddress: ArbitrumDepositPolicy.nativeUSDC))
        }
        for amount: UInt64 in [0, 1, 100_000, 1_000_000, 1_000_001, UInt64.max] {
            XCTAssertEqual(try ArbitrumDepositPolicy.units(ArbitrumDepositPolicy.formatted(amount)), amount)
        }
    }

    func testRejectsAmbiguousPrecisionAndOverflow() {
        for value in ["", ".", "-5", "+5", "1,000", "5,1", "5e3", "NaN", "５", "1.2.3", "5.0000001",
                      "18446744073709.551616", "18446744073709551615"] {
            XCTAssertThrowsError(try ArbitrumDepositPolicy.units(value), value)
        }
    }

    func testRejectsOtherNetworksAndBridgedTokens() {
        XCTAssertThrowsError(try ArbitrumDepositPolicy.validate(amount: "10", chainID: 1,
                                                              tokenAddress: ArbitrumDepositPolicy.nativeUSDC))
        XCTAssertThrowsError(try ArbitrumDepositPolicy.validate(amount: "10", chainID: 42161,
                                                              tokenAddress: "0xFF970A61A04b1cA14834A43f5de4533eBDDB5CC8"))
    }
}
