import XCTest
@testable import BSmart

final class HyperliquidQuoteLiveTests: XCTestCase {
    func testPublicMainnetBookAndVenueFeeEstimateWithoutSubmittingAnOrder() async throws {
        guard ProcessInfo.processInfo.environment["BSMART_FUNDING_LIVE_READS"] == "1" else {
            throw XCTSkip("Explicit mainnet read-only check only.")
        }
        let reader = HyperliquidExecutionReader()
        let owner = "0xa4add8273d7f47318675bdfbcce3e9648cdb4509"
        let dexs = try await reader.read(.dexs)
        let metadata = try await reader.read(.metadata(dex: "xyz"))
        let market = try HyperliquidExecutionMarket.resolve(perpDexs: dexs, meta: metadata, dex: "xyz", coin: "xyz:NVDA")
        let fees = try HyperliquidTakerFees.decode(await reader.read(.fees(owner: owner)), owner: owner)
        let bytes = try await reader.read(.book(coin: market.coin))
        let now = Date()
        let book = try HyperliquidOrderBook.decode(bytes, market: market, now: now)
        let top = try XCTUnwrap(book.asks.first)
        let nonce = UInt64(now.timeIntervalSince1970 * 1_000)
        // Public probe only: this structural intent does not establish account ownership or capacity.
        let order = try HyperliquidOrderIntent(wallet: .init(accountID: UUID(), address: owner, recoveryVerified: true),
            market: market, side: .buy, size: top.size.wire, limitPrice: top.price.wire,
            reduceOnly: false, cloid: "0x00000000000000000000000000000001", nonce: nonce, expiresAfter: nonce + 30_000)
        let quote = try HyperliquidDepthQuote.calculate(order: order, book: book, fees: fees, now: now)
        XCTAssertEqual(quote.levelsUsed, 1)
        XCTAssertTrue(quote.fullyCovered)
        XCTAssertEqual(quote.averagePrice, HyperliquidExactValue(top.price))
        XCTAssertEqual(quote.estimatedBuilderFee, .init(0))
        let evidence = """
        endpoint=\(HyperliquidExecutionReader.endpoint.absoluteString)
        publicReadProbe=\(owner)
        coin=\(market.coin)
        rawAssetID=\(market.asset)
        bookUpdatedAt=\(book.updatedAt.ISO8601Format())
        checkedAt=\(now.ISO8601Format())
        bestAsk=\(top.price.wire)
        displayedAskSize=\(top.size.wire)
        bookLevels=\(book.bids.count)/\(book.asks.count)
        userCrossRate=\(fees.userRate.wire)
        referralDiscount=\(fees.referralDiscount.wire)
        deployerFeeScale=\(market.feeContext?.deployerScale.wire ?? "missing")
        growthMode=\(market.feeContext?.growthMode.description ?? "missing")
        venueRate=\(try quote.takerRate.rounded(decimalPlaces: 12, up: true).wire)
        quoteNotional=\(try quote.notional.rounded(decimalPlaces: 6, up: true).wire)
        estimatedVenueFee=\(try quote.estimatedTakerFee.rounded(decimalPlaces: 8, up: true).wire)
        appBuilder=none (no production recipient configured)
        Read-only public market/fee estimate. No account-capacity permission, approval, device key or exchange submission.
        """
        let attachment = XCTAttachment(string: evidence)
        attachment.name = "Hyperliquid-public-depth-fee"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
