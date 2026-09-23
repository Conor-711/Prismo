import XCTest
@testable import BSmart

final class HyperliquidTradingLiveTests: XCTestCase {
    func testReadOnlySocketAndHTTPPreflightLatency() async throws {
        guard ProcessInfo.processInfo.environment["BSMART_FUNDING_LIVE_READS"] == "1" else {
            throw XCTSkip("Explicit public read-only latency measurement only.")
        }
        let wallet = DeviceWalletSummary(accountID: UUID(),
            address: "0xa4add8273d7f47318675bdfbcce3e9648cdb4509", recoveryVerified: true)
        var measurements: [String] = []
        // Actual native transports and full consistency rounds; no signer or exchange writes.
        for (useSocket, orderObservation) in [(false, false), (true, false), (true, true)] {
            let reader = HyperliquidExecutionReader(useWebSocket: useSocket, connection: HyperliquidInfoConnection())
            for index in 0..<3 {
                let start = ContinuousClock.now
                do {
                let snapshot: HyperliquidTradingSnapshot
                if orderObservation {
                    snapshot = try await HyperliquidOrderAccountObservation(reader: reader,
                        clock: { Date() }, continuousClock: { .now })
                        .snapshot(wallet: wallet, dex: "xyz", coin: "xyz:SNDK")
                } else {
                    snapshot = try await HyperliquidTradingSnapshotProvider(reader: reader)
                        .snapshot(wallet: wallet, dex: "xyz", coin: "xyz:SNDK")
                }
                async let book = HyperliquidBookObservation.read(reader: reader, market: snapshot.market,
                    clock: { Date() }, continuousClock: { .now })
                async let fees = reader.read(.fees(owner: wallet.address))
                _ = try await book
                _ = try HyperliquidTakerFees.decode(await fees, owner: wallet.address)
                try snapshot.validate(wallet: wallet, now: Date())
                let elapsed = start.duration(to: .now)
                measurements.append("transport=\(useSocket ? "socket-preferred" : "http") orderObservation=\(orderObservation) sample=\(index) preflight=\(elapsed)")
                } catch {
                    measurements.append("transport=\(useSocket ? "socket-preferred" : "http") orderObservation=\(orderObservation) sample=\(index) failed=\(error) elapsed=\(start.duration(to: .now))")
                }
            }
        }
        let report = measurements.joined(separator: "\n")
        print(report)
        let attachment = XCTAttachment(string: report + "\nPublic reads only; excludes identity, signing and submission.")
        attachment.name = "read-only-preflight-latency"; attachment.lifetime = .keepAlways; add(attachment)
    }

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
