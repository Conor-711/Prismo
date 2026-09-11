import XCTest
@testable import BSmart

final class FundingQuantityTests: XCTestCase {
    func testFullUInt256AndExactSmallFractions() throws {
        let max = try FundingQuantity(rpc: "0x" + String(repeating: "f", count: 64))
        XCTAssertEqual(max.formatted(decimals: 0), "115792089237316195423570985008687907853269984665640564039457584007913129639935")
        XCTAssertNil(max.uint64)
        XCTAssertThrowsError(try max.multiplied(by: FundingQuantity(2)))
        XCTAssertThrowsError(try max.ceilingScaled(numerator: 120, denominator: 100))
        XCTAssertEqual(try max.ceilingScaled(numerator: 1, denominator: 1), max)
        XCTAssertEqual(FundingQuantity(1).formatted(decimals: 18), "0.000000000000000001")
        XCTAssertEqual(FundingQuantity(1_230_001).formatted(decimals: 6), "1.230001")
        XCTAssertEqual(FundingQuantity(0).formatted(decimals: 6), "0")
        XCTAssertEqual(try FundingQuantity(rpc: "0x56bc75e2d63100000").formatted(decimals: 18), "100")
        XCTAssertEqual(try FundingQuantity(1).ceilingScaled(numerator: 120, denominator: 100), FundingQuantity(2))
        XCTAssertEqual(try FundingQuantity(100).ceilingScaled(numerator: 120, denominator: 100), FundingQuantity(120))
    }

    func testQuantityAndABIEncodingsAreNotInterchangeable() throws {
        for invalid in ["", "0x", "0x00", "0x01", "0X1", "0xFF", "-1", "1.2", "0xg", "0x1 ",
                        "0x" + String(repeating: "f", count: 65)] {
            XCTAssertThrowsError(try FundingQuantity(rpc: invalid), invalid)
        }
        XCTAssertThrowsError(try FundingQuantity(abi: "0x1"))
        XCTAssertThrowsError(try FundingQuantity(abi: "0x" + String(repeating: "z", count: 64)))
        let one = FundingQuantity(1)
        XCTAssertEqual(try FundingQuantity(abi: one.abi), one)
        XCTAssertThrowsError(try one.ceilingScaled(numerator: 1, denominator: 0))
    }

    func testStaticSelectorsAndReturnValidation() throws {
        XCTAssertEqual(try CCTPSourceReadCodec.call("balanceOf(address)", words: [CCTPSourceReadCodec.addressWord(PreflightTestFixture.wallet.address)]),
            "0x70a082310000000000000000000000007e5f4552091a69125d5dfcb7b8c2659029395bdf")
        XCTAssertEqual(try CCTPSourceReadCodec.call("token()"), "0xfc0c546a")
        XCTAssertFalse(try CCTPSourceReadCodec.boolean(.string(FundingQuantity(0).abi)))
        XCTAssertTrue(try CCTPSourceReadCodec.boolean(.string(FundingQuantity(1).abi)))
        XCTAssertThrowsError(try CCTPSourceReadCodec.boolean(.string(FundingQuantity(2).abi)))
        XCTAssertThrowsError(try CCTPSourceReadCodec.boolean(.string("0x0")))
        XCTAssertThrowsError(try CCTPSourceReadCodec.codeHash(.string("0x")))
    }
}
