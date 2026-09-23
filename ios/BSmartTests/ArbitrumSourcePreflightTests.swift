import XCTest
@testable import BSmart

final class ArbitrumSourcePreflightTests: XCTestCase {
    private let wallet = PreflightTestFixture.wallet

    func testSnapshotUsesOneCanonicalBlockAndExactWalletBalances() async throws {
        let rpc = try PreflightStubRPC()
        let result = try await service(rpc).snapshot(wallet: wallet)
        XCTAssertEqual(result.usdc, FundingQuantity(20_000_000))
        XCTAssertEqual(result.eth.formatted(decimals: 18), "100")
        XCTAssertEqual(result.observedCodeHashes.count, 5)
        XCTAssertEqual(result.expiresAt, PreflightTestFixture.now.addingTimeInterval(30))
        let requests = await rpc.requests
        for request in requests where [.call, .balance, .code].contains(request.method) {
            XCTAssertEqual(request.params.last, result.block.reference)
        }
        XCTAssertEqual(requests.first?.method, .chainID)
        XCTAssertThrowsError(try result.validate(wallet: wallet, now: result.expiresAt))
    }

    func testExactSignedCallHasBoundedGasAndCannotClaimCredit() async throws {
        let rpc = try PreflightStubRPC()
        let plan = try PreflightTestFixture.plan()
        let result = try await service(rpc).prepare(plan: plan, wallet: wallet, authorization: PreflightTestFixture.signature())
        XCTAssertEqual(result.callData.count, 580)
        XCTAssertEqual(result.plan.owner, wallet.address)
        XCTAssertEqual(result.gasLimit, FundingQuantity(240_000))
        XCTAssertEqual(result.maximumFeePerGas, FundingQuantity(20_000_000))
        XCTAssertEqual(result.maximumNetworkFee.formatted(decimals: 18), "0.0000048")
        XCTAssertEqual(result.sourceValue, FundingQuantity(0))
        XCTAssertEqual(result.priorityFee, FundingQuantity(0))
        let requests = await rpc.requests
        let estimate = try XCTUnwrap(requests.first(where: { $0.method == .estimate }))
        guard case .object(let transaction) = estimate.params[0] else { return XCTFail() }
        XCTAssertEqual(transaction["to"], .string(CCTPArbitrumRoute.extensionAddress))
        XCTAssertEqual(transaction["from"], .string(wallet.address))
        XCTAssertEqual(transaction["value"], .string("0x0"))
        XCTAssertEqual(transaction["data"], .string(FundingHex.encode(result.callData)))
        XCTAssertEqual(estimate.params[1], .string(result.source.block.number.rpc))
        let simulation = try XCTUnwrap(requests.first(where: {
            guard $0.method == .call, case .object(let call) = $0.params.first else { return false }
            return call["data"] == transaction["data"]
        }))
        guard case .object(let simulated) = simulation.params.first else { return XCTFail() }
        XCTAssertEqual(simulated["gas"], .string(result.gasLimit.rpc))
        XCTAssertEqual(simulated["maxFeePerGas"], .string(result.maximumFeePerGas.rpc))
        XCTAssertLessThan(try XCTUnwrap(requests.firstIndex(where: { $0.id == estimate.id })),
                          try XCTUnwrap(requests.firstIndex(where: { $0.id == simulation.id })))
        XCTAssertEqual(simulation.params.last, result.source.block.reference)
        XCTAssertThrowsError(try result.validate(wallet: wallet, now: result.expiresAt))
    }

    func testSmallFundedWalletDoesNotUseNodesFiftyMillionGasDefault() async throws {
        let rpc = try PreflightStubRPC(overrides: ["eth": .string("0x3e871b540c000")]) // 0.0011 ETH
        let result = try await service(rpc).prepare(plan: PreflightTestFixture.plan(), wallet: wallet,
                                                   authorization: PreflightTestFixture.signature())
        XCTAssertLessThan(result.maximumNetworkFee, result.source.eth)
        let requests = await rpc.requests
        for request in requests where request.method == .call {
            guard case .object(let transaction) = request.params.first,
                  transaction["maxFeePerGas"] != nil else { continue }
            XCTAssertEqual(transaction["gas"], .string(result.gasLimit.rpc))
        }
    }

    func testWrongChainCannotReceiveOwnerAddress() async throws {
        let rpc = try PreflightStubRPC(overrides: ["chainID": .string("0x1")])
        await expect(.wrongChain) { _ = try await self.service(rpc).snapshot(wallet: self.wallet) }
        let requests = await rpc.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].method, .chainID)
        XCTAssertTrue(requests[0].params.isEmpty)
    }

    func testRouteMisconfigurationAndAbsentContractsFailClosed() async throws {
        for key in ["token", "messenger", "transmitter", "minter", "remoteMessenger", "decimals", "domain", "burnLimit"] {
            let rpc = try PreflightStubRPC(overrides: [key: .string(FundingQuantity(0).abi)])
            await expect(.routeChanged) { _ = try await self.service(rpc).snapshot(wallet: self.wallet) }
        }
        for address in ArbitrumSourceReads.contracts {
            let rpc = try PreflightStubRPC(overrides: [address: .string("0x")])
            await expect(.routeChanged) { _ = try await self.service(rpc).snapshot(wallet: self.wallet) }
        }
        let nonEOA = try PreflightStubRPC(overrides: ["ownerCode": .string("0xef010000")])
        await expect(.unsupportedWallet) { _ = try await self.service(nonEOA).snapshot(wallet: self.wallet) }
    }

    func testPauseDenylistAndMalformedFlagsFailClosed() async throws {
        for key in ["usdcPaused", "transmitterPaused", "minterPaused", "ownerBlocked", "extensionBlocked", "minterBlocked",
                    "ownerDenied", "extensionDenied"] {
            let rpc = try PreflightStubRPC(overrides: [key: .string(FundingQuantity(1).abi)])
            await expect(.transferRestricted) { _ = try await self.service(rpc).snapshot(wallet: self.wallet) }
        }
        let rpc = try PreflightStubRPC(overrides: ["ownerBlocked": .string(FundingQuantity(2).abi)])
        await expect(.invalidResponse) { _ = try await self.service(rpc).snapshot(wallet: self.wallet) }
    }

    func testStaleFutureReorganizedAndMissingDataCannotPass() async throws {
        for skew in [-60.0, 16.0] {
            let rpc = try PreflightStubRPC(blockTime: PreflightTestFixture.now.addingTimeInterval(skew))
            await expect(.staleState) { _ = try await self.service(rpc).snapshot(wallet: self.wallet) }
        }
        let changed = try PreflightStubRPC(reorg: true)
        await expect(.staleState) { _ = try await self.service(changed).snapshot(wallet: self.wallet) }
        for key in ["eth", "usdc", "nonce"] {
            let rpc = try PreflightStubRPC(overrides: [key: .null])
            await expect(.invalidResponse) { _ = try await self.service(rpc).snapshot(wallet: self.wallet) }
        }
    }

    func testInsufficientFundsUsedAuthorizationNonceAndFeeLimits() async throws {
        for (key, value, error) in [
            ("usdc", .string(FundingQuantity(9_999_999).abi), FundingPreflightError.insufficientUSDC),
            ("eth", .string("0x0"), .insufficientETH),
            ("eth", .string("0x1"), .insufficientETH),
            ("allowance", .string(FundingQuantity(0).abi), .routeChanged),
            ("burnLimit", .string(FundingQuantity(1).abi), .routeChanged),
            ("authorization", .string(FundingQuantity(1).abi), .authorizationUsed),
            ("pendingNonce", .string("0x1"), .pendingTransaction),
            ("gasPrice", .string("0x0"), .invalidResponse),
            ("gas", .string("0x1"), .invalidResponse),
            ("gas", .string("0x989680"), .excessiveFee),
            ("gasPrice", .string("0x174876e800"), .excessiveFee),
            ("simulation", .string(FundingQuantity(0).abi), .simulationFailed)
        ] as [(String, FundingRPCValue, FundingPreflightError)] {
            let rpc = try PreflightStubRPC(overrides: [key: value])
            await expect(error) { _ = try await self.service(rpc).prepare(plan: PreflightTestFixture.plan(),
                wallet: self.wallet, authorization: PreflightTestFixture.signature()) }
        }
        let changed = try PreflightStubRPC(changedNonce: true)
        await expect(.pendingTransaction) { _ = try await self.service(changed).prepare(plan: PreflightTestFixture.plan(),
            wallet: self.wallet, authorization: PreflightTestFixture.signature()) }
    }

    func testInvalidSignatureOrSwitchedAccountCannotReachRPC() async throws {
        let rpc = try PreflightStubRPC()
        do {
            _ = try await service(rpc).prepare(plan: PreflightTestFixture.plan(), wallet: wallet, authorization: "0x")
            XCTFail()
        } catch { XCTAssertEqual(error as? CCTPFundingError, .invalidPlan) }
        let changed = DeviceWalletSummary(accountID: UUID(), address: wallet.address, recoveryVerified: true)
        do {
            _ = try await service(rpc).prepare(plan: PreflightTestFixture.plan(), wallet: changed,
                authorization: PreflightTestFixture.signature())
            XCTFail()
        } catch { XCTAssertEqual(error as? CCTPFundingError, .invalidPlan) }
        let requests = await rpc.requests
        XCTAssertTrue(requests.isEmpty)
    }

    private func service(_ rpc: PreflightStubRPC) -> ArbitrumSourcePreflight {
        .init(rpc: rpc, clock: { PreflightTestFixture.now })
    }

    private func expect(_ expected: FundingPreflightError, operation: () async throws -> Void) async {
        do { try await operation(); XCTFail("Expected \(expected)") }
        catch { XCTAssertEqual(error as? FundingPreflightError, expected) }
    }
}

enum PreflightTestFixture {
    static let now = Date(timeIntervalSince1970: 1_770_000_000)
    static let wallet = DeviceWalletSummary(accountID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        address: "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf", recoveryVerified: true)

    static func plan() throws -> CCTPDepositPlan {
        let schedule = try CCTPFeeSchedule.decode(Data(CCTPDepositQuoteTests.response.utf8), receivedAt: now)
        return try .init(wallet: wallet, quote: CCTPDepositQuote(amount: "10", schedule: schedule, now: now),
            now: now, nonce: Data(repeating: 17, count: 32))
    }

    static func signature() throws -> String {
        let url = try XCTUnwrap(Bundle(for: ArbitrumSourcePreflightTests.self).url(forResource: "cctp-deposit-vector", withExtension: "json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return try XCTUnwrap(json["signature"] as? String)
    }

    static func block(time: Date = now, reorg: Bool = false) -> FundingRPCValue {
        .object(["number": .string("0x1234"), "hash": .string("0x" + String(repeating: reorg ? "22" : "11", count: 32)),
            "timestamp": .string(FundingQuantity(UInt64(time.timeIntervalSince1970)).rpc), "baseFeePerGas": .string("0x989680")])
    }
}

actor PreflightStubRPC: ArbitrumFundingRPCProviding {
    private(set) var requests: [FundingRPCRequest] = []
    private let fields: [(String, FundingRPCRequest)]
    private let overrides: [String: FundingRPCValue]
    private let blockTime: Date
    private let reorg: Bool
    private let changedNonce: Bool
    private let authorizationNonce: Data
    private let owner: String
    private var blockCount = 0
    private var pendingCount = 0

    init(overrides: [String: FundingRPCValue] = [:], blockTime: Date = PreflightTestFixture.now,
         reorg: Bool = false, changedNonce: Bool = false, authorizationNonce: Data = Data(repeating: 17, count: 32),
         owner: String = PreflightTestFixture.wallet.address) throws {
        self.overrides = overrides
        self.blockTime = blockTime
        self.reorg = reorg
        self.changedNonce = changedNonce
        self.authorizationNonce = authorizationNonce
        self.owner = owner
        let block = try ArbitrumFundingBlock(PreflightTestFixture.block(), now: PreflightTestFixture.now)
        fields = try ArbitrumSourceReads(owner: owner, block: block).fields
    }

    func read(_ requests: [FundingRPCRequest]) async throws -> [FundingRPCValue] {
        self.requests += requests
        return try requests.map { request in
            switch request.method {
            case .chainID: return overrides["chainID"] ?? .string("0xa4b1")
            case .block:
                blockCount += 1
                return PreflightTestFixture.block(time: blockTime, reorg: reorg && blockCount > 1)
            case .nonce where request.params.last == .string("pending"):
                pendingCount += 1
                return overrides["pendingNonce"] ?? .string(changedNonce && pendingCount > 1 ? "0x1" : "0x0")
            case .gasPrice: return overrides["gasPrice"] ?? .string("0x989680")
            case .estimate: return overrides["gas"] ?? .string("0x30d40")
            default: break
            }
            if let (key, _) = fields.first(where: { $0.1.method == request.method && $0.1.params.first == request.params.first }) {
                if let override = overrides[key] { return override }
                switch key {
                case "eth": return .string("0x56bc75e2d63100000")
                case "nonce": return .string("0x0")
                case "ownerCode": return .string("0x")
                case "usdc": return .string(FundingQuantity(20_000_000).abi)
                case "decimals": return .string(FundingQuantity(6).abi)
                case "domain": return .string(FundingQuantity(3).abi)
                case "token": return .string(try CCTPSourceReadCodec.addressWord(ArbitrumDepositPolicy.nativeUSDC))
                case "messenger", "remoteMessenger": return .string(try CCTPSourceReadCodec.addressWord(CCTPArbitrumRoute.tokenMessenger))
                case "minter": return .string(try CCTPSourceReadCodec.addressWord(CCTPArbitrumRoute.tokenMinter))
                case "transmitter": return .string(try CCTPSourceReadCodec.addressWord(CCTPArbitrumRoute.messageTransmitter))
                case "allowance", "burnLimit": return .string(FundingQuantity(10_000_000_000_000).abi)
                case let address where ArbitrumSourceReads.contracts.contains(address): return .string("0x6001600055")
                default: return .string(FundingQuantity(0).abi)
                }
            }
            guard request.method == .call, case .object(let tx) = request.params.first,
                  let data = try tx["data"]?.text() else { throw FundingPreflightError.invalidResponse }
            if data.count > 1_000 { return overrides["simulation"] ?? .string("0x") }
            let authorization = try CCTPSourceReadCodec.call("authorizationState(address,bytes32)", words: [
                CCTPSourceReadCodec.addressWord(owner), FundingHex.encode(authorizationNonce)])
            guard data == authorization else { throw FundingPreflightError.invalidResponse }
            return overrides["authorization"] ?? .string(FundingQuantity(0).abi)
        }
    }
}
