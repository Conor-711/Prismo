import XCTest
@testable import BSmart

final class HyperliquidFeeTests: XCTestCase {
    private typealias Q = HyperliquidQuoteFixture
    private typealias F = HyperliquidTradingFixture

    func testExactArithmeticDoesNotRoundIntermediateFractions() throws {
        let third = try Q.exact("1").divided(by: .init(3))
        XCTAssertEqual(try third.multiplied(by: .init(3)), .init(1))
        XCTAssertEqual(try third.rounded(decimalPlaces: 6, up: false).wire, "0.333333")
        XCTAssertEqual(try third.rounded(decimalPlaces: 6, up: true).wire, "0.333334")
        XCTAssertEqual(try Q.exact("0.1").adding(Q.exact("0.2")), try Q.exact("0.3"))
        XCTAssertEqual(try Q.exact("9007199254740993.000000000000000001").subtracting(Q.exact("9007199254740993")),
                       try Q.exact("0.000000000000000001"))
    }
    func testArithmeticRejectsUnderflowDivisionByZeroAndUnsafeOutput() throws {
        XCTAssertThrowsError(try Q.exact("1").subtracting(.init(2)))
        XCTAssertThrowsError(try Q.exact("1").divided(by: .init(0)))
        XCTAssertThrowsError(try Q.exact("1").rounded(decimalPlaces: 19, up: true))
        let huge = try Q.exact("1000000000000000000000000000000000000000000000000000000000000000000000000000")
        XCTAssertThrowsError(try huge.multiplied(by: huge).rounded(decimalPlaces: 0, up: true))
    }
    func testVenueScaleGrowthAndReferralAreIndependentOfAppFee() throws {
        let fees = try HyperliquidTakerFees.decode(Q.fees(discount: "0.04"), owner: F.wallet.address)
        for (scale, growth, multiplier) in [("0", false, "1"), ("0.5", false, "1.5"), ("1", false, "2"),
            ("3", false, "6"), ("0", true, "0.1"), ("1", true, "0.2"), ("3.01", true, "0.602"), ("9.99", true, "1.998")] {
            let market = try Q.market(scale: scale, growth: growth ? "enabled" : "disabled")
            XCTAssertEqual(try market.feeContext?.multiplier(), try Q.exact(multiplier))
            XCTAssertEqual(try fees.rate(market: market), try Q.exact("0.000384").multiplied(by: Q.exact(multiplier)))
        }
    }
    func testNativeZeroAndNormalMarginMetadata() throws {
        let market = try Q.market(scale: "0.00", growth: nil, native: true)
        XCTAssertFalse(market.isolatedOnly)
        XCTAssertEqual(market.marginRestriction, .normal)
        let fees = try HyperliquidTakerFees.decode(Q.fees(), owner: F.wallet.address)
        XCTAssertEqual(try fees.rate(market: market), try Q.exact("0.0004"))
        XCTAssertThrowsError(try Q.market(overrides: ["onlyIsolated": true]))
        XCTAssertThrowsError(try Q.market(scale: "1", growth: nil, native: true))
        XCTAssertThrowsError(try Q.market(scale: "0", native: true))
    }
    func testInvalidAndMissingVenueFeeMetadataCannotMeanFree() throws {
        for (scale, growth) in [("3.01", "disabled"), ("10", "enabled"), ("-1", "disabled"), ("1", "future")] {
            XCTAssertThrowsError(try Q.market(scale: scale, growth: growth))
        }
        let fees = try HyperliquidTakerFees.decode(Q.fees(), owner: F.wallet.address)
        XCTAssertThrowsError(try fees.rate(market: Q.market(scale: nil)))
    }
    func testMalformedFeesAndDiscountsAreRejected() throws {
        for data in [Data("{}".utf8), Data("null".utf8), Data(repeating: 32, count: 262_145),
                     try Q.fees(rate: "-0.001"), try Q.fees(rate: "1"), try Q.fees(discount: "1.001"),
                     try F.data(["userCrossRate": 0.0004, "activeReferralDiscount": "0"])] {
            XCTAssertThrowsError(try HyperliquidTakerFees.decode(data, owner: F.wallet.address))
        }
    }
    func testBuilderFeeUnitsLimitsAndCanonicalRecipient() throws {
        let fee = try HyperliquidBuilderFee(address: Q.recipient.uppercased(), tenthsOfBasisPoint: 10)
        XCTAssertEqual(fee.address, Q.recipient)
        XCTAssertEqual(try fee.rate, try Q.exact("0.0001"))
        XCTAssertEqual(try HyperliquidBuilderFee(address: Q.recipient, tenthsOfBasisPoint: 100).rate, try Q.exact("0.001"))
        for rate: UInt16 in [0, 101, .max] {
            XCTAssertThrowsError(try HyperliquidBuilderFee(address: Q.recipient, tenthsOfBasisPoint: rate))
        }
        XCTAssertThrowsError(try HyperliquidBuilderFee(address: "0x" + String(repeating: "0", count: 40), tenthsOfBasisPoint: 10))
    }
    func testBuilderApprovalBindsOwnerRecipientAndCeiling() throws {
        let fee = try HyperliquidBuilderFee(address: Q.recipient, tenthsOfBasisPoint: 10)
        let approval = try HyperliquidBuilderApproval.decode(Data("10".utf8), owner: F.wallet.address, fee: fee)
        XCTAssertNoThrow(try approval.validate(owner: F.wallet.address, fee: fee))
        XCTAssertThrowsError(try approval.validate(owner: Q.recipient, fee: fee))
        XCTAssertThrowsError(try approval.validate(owner: F.wallet.address,
            fee: .init(address: F.wallet.address, tenthsOfBasisPoint: 10)))
        for text in ["null", "true", "\"10\"", "-1", "9", "10.5", "1001", "65536", "{}"] {
            XCTAssertThrowsError(try HyperliquidBuilderApproval.decode(Data(text.utf8), owner: F.wallet.address, fee: fee))
        }
        XCTAssertNoThrow(try HyperliquidBuilderApproval.decode(Data("1000".utf8), owner: F.wallet.address, fee: fee))
    }
}
