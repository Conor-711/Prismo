import XCTest
@testable import BSmart

final class CCTPWithdrawalFeeLiveTests: XCTestCase {
    func testMainnetContractFeeOnlyWithoutWalletOrTransaction() async throws {
        guard ProcessInfo.processInfo.environment["BSMART_FUNDING_LIVE_READS"] == "1" else {
            throw XCTSkip("Explicit opt-in required for public mainnet contract reads.")
        }
        let rpc = WithdrawalLiveReadProbe()
        let value: CCTPWithdrawalFeeSnapshot
        do { value = try await CCTPWithdrawalFeeReader(rpc: rpc).snapshot() }
        catch {
            let diagnostic = XCTAttachment(string: await rpc.diagnostic)
            diagnostic.name = "withdrawal-public-read-failure"; diagnostic.lifetime = .keepAlways; add(diagnostic)
            XCTFail("Public read failed: \(await rpc.diagnostic)")
            throw error
        }
        try value.validate(now: Date())
        let attachment = XCTAttachment(string: """
        endpoint=\(HyperEVMFundingRPC.endpoint)
        contract=\(CCTPArbitrumRoute.coreDepositWallet)
        block=\(value.head.number)
        blockHash=\(value.head.hash)
        codeHash=\(value.contractCodeHash)
        maximumCCTPFeeUSDC=\(value.maximumCCTPFee.formatted(decimals: 6))
        checkedAt=\(value.checkedAt.ISO8601Format())
        CCTP configuration only; not total fees, a signed fee ceiling, or withdrawal acceptance.
        """)
        attachment.name = "CCTP-withdrawal-public-fee"
        attachment.lifetime = .keepAlways; add(attachment)
    }
}

private actor WithdrawalLiveReadProbe: FundingRPCProviding {
    private let rpc = HyperEVMFundingRPC()
    private(set) var diagnostic = "No request"
    func read(_ requests: [FundingRPCRequest]) async throws -> [FundingRPCValue] {
        let methods = requests.map(\.method.rawValue).joined(separator: ",")
        diagnostic = methods
        do {
            let values = try await rpc.read(requests)
            diagnostic = methods + " returned " + String(values.count)
            return values
        } catch {
            diagnostic = methods + " failed " + String(describing: error)
            throw error
        }
    }
}
