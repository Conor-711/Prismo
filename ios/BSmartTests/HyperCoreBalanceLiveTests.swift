import XCTest
@testable import BSmart

// Explicit opt-in public reads. These addresses are not user wallets or deposit destinations.
final class HyperCoreBalanceLiveTests: XCTestCase {
    func testMainnetBalanceModesUsingPublicReadProbes() async throws {
        guard ProcessInfo.processInfo.environment["BSMART_FUNDING_LIVE_READS"] == "1" else {
            throw XCTSkip("Enable BSMART_FUNDING_LIVE_READS only for an explicit mainnet read-only check.")
        }
        let provider = HyperCoreBalanceProvider()
        for owner in [CCTPArbitrumRoute.coreDepositWallet, "0x50c17b4794607dde1077686a70fa4ba3064b4985"] {
            let probe = DeviceWalletSummary(accountID: UUID(), address: owner, recoveryVerified: false)
            let result = try await provider.snapshot(wallet: probe)
            try result.validate(wallet: probe, now: Date())
            XCTAssertEqual(result.owner, owner)
            XCTAssertEqual(result.mode.usesSharedBalance, result.perps == nil)
            let evidence = """
            endpoint=\(HyperCoreBalanceClient.endpoint.absoluteString)
            publicReadProbe=\(owner)
            mode=\(result.mode.rawValue)
            usdc=\(result.usdc.formatted)
            hold=\(result.held.formatted)
            defaultPerpsEquity=\(result.perps?.equity.formatted ?? "not-used-for-shared-balances")
            defaultPerpsWithdrawable=\(result.perps?.withdrawable.formatted ?? "not-queried")
            requestedAt=\(result.requestedAt.ISO8601Format())
            checkedAt=\(result.checkedAt.ISO8601Format())
            Not an atomic snapshot, user-wallet registration, deposit receipt, or trade authorization.
            """
            let attachment = XCTAttachment(string: evidence)
            attachment.name = "HyperCore-public-balance-\(owner.suffix(8))"
            attachment.lifetime = .keepAlways; add(attachment)
        }
    }
}
