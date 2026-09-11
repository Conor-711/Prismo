import XCTest
@testable import BSmart

final class CCTPSourceGasBudgetTests: XCTestCase {
    func testExactRoundingAndTheHigherBaseFeeWin() throws {
        let value = try budget(gas: 200_001, price: 1)
        XCTAssertEqual(value.gasLimit, FundingQuantity(240_002))
        XCTAssertEqual(value.maximumFeePerGas, FundingQuantity(20_000_000))
        XCTAssertEqual(value.maximumNetworkFee, FundingQuantity(4_800_040_000_000))
    }

    func testMaximumGasAndNetworkFeeBoundaries() throws {
        XCTAssertEqual(try budget(gas: 4_166_666).gasLimit, FundingQuantity(5_000_000))
        XCTAssertThrowsError(try budget(gas: 4_166_667))
        XCTAssertEqual(try budget(gas: 208_333, price: 20_000_000_000).maximumNetworkFee,
                       FundingQuantity(10_000_000_000_000_000))
        XCTAssertThrowsError(try budget(gas: 208_334, price: 20_000_000_000))
    }

    func testZeroAndOverflowAreNotFeeQuotes() throws {
        XCTAssertThrowsError(try budget(gas: 20_999))
        XCTAssertThrowsError(try budget(gas: 200_000, price: 0))
        XCTAssertThrowsError(try CCTPSourceGasBudget.feePerGas(gasPrice: FundingQuantity(1), baseFee: FundingQuantity(0)))
        let maximum = try FundingQuantity(rpc: "0x" + String(repeating: "f", count: 64))
        XCTAssertThrowsError(try CCTPSourceGasBudget.feePerGas(gasPrice: maximum, baseFee: FundingQuantity(1)))
        XCTAssertThrowsError(try CCTPSourceGasBudget(estimatedGas: maximum, gasPrice: FundingQuantity(1), baseFee: FundingQuantity(1)))
    }

    private func budget(gas: UInt64, price: UInt64 = 10_000_000) throws -> CCTPSourceGasBudget {
        try .init(estimatedGas: FundingQuantity(gas), gasPrice: FundingQuantity(price), baseFee: FundingQuantity(10_000_000))
    }
}
