import XCTest
@testable import BSmart

final class HyperliquidOrderBookTests: XCTestCase {
    private typealias Q = HyperliquidQuoteFixture
    private typealias F = HyperliquidTradingFixture

    func testExactFullPrecisionBookAndEmptySide() throws {
        let book = try decode(Q.book())
        XCTAssertEqual(book.bids.map(\.price.wire), ["219", "218"])
        XCTAssertEqual(book.asks.map(\.size.wire), ["1", "2"])
        XCTAssertTrue(try decode(Q.book(bids: [], asks: [])).asks.isEmpty)
    }
    func testStaleFutureAndNonFiniteTimesAreRejected() throws {
        for delta: TimeInterval in [-5, 2.001] { XCTAssertThrowsError(try decode(Q.book(at: F.now.addingTimeInterval(delta)))) }
        let book = try decode(Q.book(at: F.now.addingTimeInterval(-4.9)))
        XCTAssertThrowsError(try book.validate(now: F.now.addingTimeInterval(0.1)))
        XCTAssertThrowsError(try book.validate(now: Date(timeIntervalSince1970: .nan)))
    }
    func testWrongCoinCrossedUnsortedAndDuplicatePricesAreRejected() throws {
        for data in [try Q.book(coin: "NVDA"), try Q.book(bids: [Q.level("220", "1")]),
                     try Q.book(bids: [Q.level("218", "1"), Q.level("219", "1")]),
                     try Q.book(asks: [Q.level("221", "1"), Q.level("220", "1")]),
                     try Q.book(asks: [Q.level("220", "1"), Q.level("220.0", "1")])] {
            XCTAssertThrowsError(try decode(data))
        }
    }
    func testMalformedPrecisionSizesOrderCountsAndBounds() throws {
        var zeroCount = Q.level("220", "1"); zeroCount["n"] = 0
        var fractionalCount = zeroCount; fractionalCount["n"] = 1.5
        var numericPrice = zeroCount; numericPrice["px"] = 220
        for row in [Q.level("220.001", "1"), Q.level("220", "0.0001"), Q.level("0", "1"),
                    Q.level("220", "0"), Q.level("220", "-1"), zeroCount, fractionalCount, numericPrice] {
            XCTAssertThrowsError(try decode(Q.book(asks: [row])))
        }
        XCTAssertThrowsError(try decode(Q.book(asks: (220...240).map { Q.level(String($0), "1") })))
        XCTAssertThrowsError(try decode(Data(repeating: 32, count: 65_537)))
        XCTAssertThrowsError(try decode(F.data(["coin": F.coin, "time": 1, "levels": []])))
    }
    private func decode(_ data: Data) throws -> HyperliquidOrderBook {
        try .decode(data, market: Q.market(), now: F.now)
    }
}

final class HyperliquidDepthQuoteTests: XCTestCase {
    private typealias Q = HyperliquidQuoteFixture
    private typealias F = HyperliquidTradingFixture

    func testBuyWalksAsksAndSeparatesVenueAndBuilderFees() throws {
        let builder = try HyperliquidBuilderFee(address: Q.recipient, tenthsOfBasisPoint: 10)
        let quote = try calculate(Q.order(builder: builder))
        XCTAssertTrue(quote.fullyCovered)
        XCTAssertEqual(quote.quotedSize, try Q.exact("2.5"))
        XCTAssertEqual(quote.notional, try Q.exact("551.5"))
        XCTAssertEqual(quote.averagePrice, try Q.exact("220.6"))
        XCTAssertEqual(quote.estimatedTakerFee, try Q.exact("0.04412"))
        XCTAssertEqual(quote.estimatedBuilderFee, try Q.exact("0.05515"))
        XCTAssertEqual(quote.estimatedTotalFee, try Q.exact("0.09927"))
        XCTAssertEqual(quote.levelsUsed, 2)
        XCTAssertEqual(try quote.impactBasisPoints.rounded(decimalPlaces: 4, up: false).wire, "27.2727")
    }
    func testSellUsesBidSideAndDoesNotTreatLimitAsMaximumNotional() throws {
        let quote = try calculate(Q.order(side: .sell, size: "2", price: "217"))
        XCTAssertEqual(quote.notional, try Q.exact("437"))
        XCTAssertGreaterThan(quote.notional, try Q.exact("434"))
        XCTAssertEqual(quote.averagePrice, try Q.exact("218.5"))
        XCTAssertEqual(quote.estimatedTakerFee, try Q.exact("0.03496"))
        XCTAssertEqual(quote.estimatedBuilderFee, .init(0))
        XCTAssertEqual(quote.estimatedTotalFee, quote.estimatedTakerFee)
    }
    func testLimitAndReturnedDepthLeaveUncoveredSize() throws {
        let limited = try calculate(Q.order(price: "220"))
        XCTAssertFalse(limited.fullyCovered)
        XCTAssertEqual(limited.quotedSize, .init(1))
        XCTAssertEqual(limited.uncoveredSize, try Q.exact("1.5"))
        XCTAssertEqual(limited.levelsUsed, 1)
        let shallow = try calculate(Q.order(size: "10", price: "300"))
        XCTAssertEqual(shallow.quotedSize, .init(3))
        XCTAssertEqual(shallow.uncoveredSize, .init(7))
    }
    func testNoLiquidityAndMismatchedScopeNeverYieldZeroPrice() throws {
        XCTAssertThrowsError(try calculate(Q.order(price: "219")))
        XCTAssertThrowsError(try calculate(Q.order(), data: Q.book(asks: [])))
        let book = try HyperliquidOrderBook.decode(Q.book(), market: Q.market(), now: F.now)
        let fees = try HyperliquidTakerFees.decode(Q.fees(), owner: Q.recipient)
        XCTAssertThrowsError(try HyperliquidDepthQuote.calculate(order: Q.order(), book: book, fees: fees, now: F.now))
        XCTAssertThrowsError(try HyperliquidDepthQuote.calculate(order: Q.order(market: Q.market(scale: "2")),
            book: book, fees: .decode(Q.fees(), owner: F.wallet.address), now: F.now))
    }
    func testBuilderFeeDoesNotReceiveReferralOrGrowthDiscount() throws {
        let order = try Q.order(builder: .init(address: Q.recipient, tenthsOfBasisPoint: 10))
        let book = try HyperliquidOrderBook.decode(Q.book(), market: order.market, now: F.now)
        let fees = try HyperliquidTakerFees.decode(Q.fees(discount: "1"), owner: F.wallet.address)
        let quote = try HyperliquidDepthQuote.calculate(order: order, book: book, fees: fees, now: F.now)
        XCTAssertEqual(quote.estimatedTakerFee, .init(0))
        XCTAssertEqual(quote.estimatedTotalFee, try Q.exact("0.05515"))
    }
    private func calculate(_ order: HyperliquidOrderIntent, data: Data? = nil) throws -> HyperliquidDepthQuote {
        try .calculate(order: order, book: .decode(data ?? Q.book(), market: order.market, now: F.now),
                       fees: .decode(Q.fees(), owner: F.wallet.address), now: F.now)
    }
}
