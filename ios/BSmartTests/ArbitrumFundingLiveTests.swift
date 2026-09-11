import XCTest
@testable import BSmart

// Explicit opt-in diagnostic, not a network dependency of the offline test suite.
final class ArbitrumFundingLiveTests: XCTestCase {
    func testReadOnlyMainnetSourceSnapshot() async throws {
        guard ProcessInfo.processInfo.environment["BSMART_FUNDING_LIVE_READS"] == "1" else {
            throw XCTSkip("Enable BSMART_FUNDING_LIVE_READS only for an explicit mainnet read-only check.")
        }
        // Public burn-address read probe, not a device-wallet registration or a funding destination.
        // The public key-1 vector is delegated on mainnet and must remain rejected as non-EOA.
        let probe = DeviceWalletSummary(accountID: PreflightTestFixture.wallet.accountID,
            address: "0x000000000000000000000000000000000000dead", recoveryVerified: false)
        let result = try await ArbitrumSourcePreflight().snapshot(wallet: probe)
        XCTAssertEqual(result.owner, probe.address)
        XCTAssertEqual(result.observedCodeHashes.count, 5)
        try result.validate(wallet: probe, now: Date())
        let evidence = """
        chain=42161
        owner=\(result.owner)
        block=\(result.block.number.rpc)
        hash=\(result.block.hash)
        timestamp=\(result.block.timestamp.ISO8601Format())
        usdcUnits=\(result.usdc.formatted(decimals: 0))
        ethWei=\(result.eth.formatted(decimals: 0))
        contracts=\(result.observedCodeHashes.sorted(by: { $0.key < $1.key }))
        """
        let attachment = XCTAttachment(string: evidence)
        attachment.name = "Arbitrum-mainnet-source-read-only"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
