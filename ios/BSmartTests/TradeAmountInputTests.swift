import XCTest
@testable import BSmart

final class TradeAmountInputTests: XCTestCase {
    func testLiveEntryKeepsExactSixDecimalNotional() {
        var input = TradeAmountInput(text: "100.000001", fractionDigits: 6)
        XCTAssertEqual(input.text, "100.000001")
        input.enter("2")
        XCTAssertEqual(input.text, "100.000001")
        input.setExact("2.994180")
        XCTAssertEqual(input.text, "2.99418")
        for invalid in ["-10", "1e3", "NaN", "100000000", "0.0000001"] { input.setExact(invalid) }
        XCTAssertEqual(input.text, "2.99418")
    }

    func testKeypadAcceptsOnlyTwoDecimalPlacesAndOneSeparator() {
        var input = TradeAmountInput()
        ["0", ".", "1", ".", "2", "3", "A"].forEach { input.enter($0) }
        XCTAssertEqual(input.text, "0.12")
        XCTAssertEqual(input.value, 0.12)
    }

    func testDeletingAmountReturnsToZero() {
        var input = TradeAmountInput()
        ["2", "5", "0"].forEach { input.enter($0) }
        XCTAssertEqual(input.text, "250")
        (0..<5).forEach { _ in input.enter("delete") }
        XCTAssertEqual(input.text, "0")
        XCTAssertEqual(input.value, 0)
    }

    func testInputRemainsBoundedAndPresetFloorsCents() {
        var input = TradeAmountInput()
        (0..<14).forEach { _ in input.enter("9") }
        XCTAssertEqual(input.text, "99999999")
        input.set(12.999)
        XCTAssertEqual(input.text, "12.99")
        input.set(.infinity)
        XCTAssertEqual(input.value, 0)
    }

    func testMaximumReservesFeeAndNeverRoundsAboveBalance() {
        for leverage in [1, 5, 20] {
            let amount = TradeAmountInput.maximumMargin(balance: 100, leverage: leverage, feeRate: 0.00045)
            XCTAssertLessThanOrEqual(amount * (1 + Double(leverage) * 0.00045), 100)
            XCTAssertGreaterThan(amount, 99)
        }
        XCTAssertEqual(TradeAmountInput.maximumMargin(balance: -1, leverage: 5, feeRate: 0.00045), 0)
    }

    func testStaleAndFutureQuotesCannotEnableSubmission() {
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertTrue(TradeAmountInput.quoteIsCurrent(now.addingTimeInterval(-3), now: now))
        XCTAssertFalse(TradeAmountInput.quoteIsCurrent(now.addingTimeInterval(-31), now: now))
        XCTAssertFalse(TradeAmountInput.quoteIsCurrent(now.addingTimeInterval(10), now: now))
    }
}
