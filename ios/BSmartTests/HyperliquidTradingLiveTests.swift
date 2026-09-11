import XCTest
@testable import BSmart

final class HyperliquidTradingLiveTests: XCTestCase {
    func testPublicMainnetAccountMarketObservation() async throws {
        guard ProcessInfo.processInfo.environment["BSMART_FUNDING_LIVE_READS"] == "1" else {
            throw XCTSkip("Explicit mainnet read-only check only.")
        }
        // A public data probe, not wallet creation, backup verification or execution permission.
        let owner = "0xa4add8273d7f47318675bdfbcce3e9648cdb4509"
        let probe = DeviceWalletSummary(accountID: UUID(), address: owner, recoveryVerified: true)
        let result = try await HyperliquidTradingSnapshotProvider().snapshot(wallet: probe, dex: "xyz", coin: "xyz:NVDA")
        try result.validate(wallet: probe, now: Date())
        XCTAssertEqual(result.owner, owner)
        XCTAssertEqual(result.market.coin, "xyz:NVDA")
        XCTAssertEqual(result.market.collateralToken, 0)
        let evidence = """
        endpoint=\(HyperliquidExecutionReader.endpoint.absoluteString)
        publicReadProbe=\(owner)
        mode=\(result.mode.rawValue)
        coin=\(result.market.coin)
        rawAssetID=\(result.market.asset)
        leverage=\(result.active.leverage.mode.rawValue) \(result.active.leverage.multiplier)x
        markPrice=\(result.active.markPrice.wire)
        maxTradeSzs[buy]=\(result.active.buy.maximumSize.wire)
        maxTradeSzs[sell]=\(result.active.sell.maximumSize.wire)
        availableToTrade[buy]=\(result.active.buy.availableToTrade.wire)
        availableToTrade[sell]=\(result.active.sell.availableToTrade.wire)
        positionMagnitude=\(result.position?.quantity.magnitude.wire ?? "none")
        positionNegative=\(result.position?.quantity.isNegative.description ?? "none")
        positionsUpdatedAt=\(result.positions.updatedAt.ISO8601Format())
        requestedAt=\(result.requestedAt.ISO8601Format())
        checkedAt=\(result.checkedAt.ISO8601Format())
        expiresAt=\(result.expiresAt.ISO8601Format())
        Nonatomic read-only observation. Not deposit attribution, consent, or full trade preflight.
        """
        let attachment = XCTAttachment(string: evidence)
        attachment.name = "Hyperliquid-public-account-market"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
