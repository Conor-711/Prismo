import Foundation

protocol ArbitrumWalletSnapshotProviding: Sendable {
    func snapshot(wallet: DeviceWalletSummary) async throws -> ArbitrumWalletSnapshot
}

protocol CCTPSourcePreparing: ArbitrumWalletSnapshotProviding {
    func prepare(plan: CCTPDepositPlan, wallet: DeviceWalletSummary, authorization: String) async throws -> CCTPSourcePreflight
}

struct ArbitrumSourcePreflight: ArbitrumWalletSnapshotProviding, CCTPSourcePreparing, Sendable {
    private let rpc: ArbitrumFundingRPCProviding
    private let clock: @Sendable () -> Date

    init(rpc: ArbitrumFundingRPCProviding = ArbitrumFundingRPC(), clock: @escaping @Sendable () -> Date = { Date() }) {
        self.rpc = rpc
        self.clock = clock
    }

    func snapshot(wallet: DeviceWalletSummary) async throws -> ArbitrumWalletSnapshot {
        guard TradingWalletChallenge.validAddress(wallet.address), wallet.address == wallet.address.lowercased() else {
            throw FundingPreflightError.unsupportedWallet
        }
        // Do not disclose the owner until this endpoint reports the intended chain.
        try await verifyChain()
        let head = try await read([.init(.block, [.string("latest"), .bool(false)])])
        let block = try ArbitrumFundingBlock(head[0], now: clock())
        let request = try ArbitrumSourceReads(owner: wallet.address, block: block)
        let values = try await read(request.fields.map(\.1))
        let snapshot = try request.snapshot(values, wallet: wallet, block: block, now: clock())
        try await verifyCanonical(block)
        try snapshot.validate(wallet: wallet, now: clock())
        return snapshot
    }

    func prepare(plan: CCTPDepositPlan, wallet: DeviceWalletSummary, authorization: String) async throws -> CCTPSourcePreflight {
        // Validates the signature against this exact plan before any RPC can receive it.
        let data = try CCTPDepositCodec.callData(plan: plan, wallet: wallet, authorization: authorization, now: clock())
        let source = try await snapshot(wallet: wallet)
        try plan.validateAuthorization(wallet: wallet, now: clock())
        guard source.block.timestamp.timeIntervalSince1970 > TimeInterval(plan.validAfter),
              source.block.timestamp.timeIntervalSince1970 < TimeInterval(plan.validBefore) else { throw FundingPreflightError.staleState }
        let amount = FundingQuantity(plan.quote.amountUnits)
        guard source.usdc >= amount else { throw FundingPreflightError.insufficientUSDC }
        guard source.eth > FundingQuantity(0) else { throw FundingPreflightError.insufficientETH }
        guard source.burnLimit >= amount, source.extensionAllowance >= amount else { throw FundingPreflightError.routeChanged }
        let authRequest = try ArbitrumSourceReads.call(ArbitrumDepositPolicy.nativeUSDC, "authorizationState(address,bytes32)",
            [CCTPSourceReadCodec.addressWord(plan.owner), FundingHex.encode(plan.authorizationNonce)], block: source.block)
        let checks = try await read([authRequest, .init(.nonce, [.string(plan.owner), .string("pending")]), .init(.gasPrice)])
        guard try !CCTPSourceReadCodec.boolean(checks[0]) else { throw FundingPreflightError.authorizationUsed }
        let nonce = try FundingQuantity(rpc: checks[1].text())
        guard nonce == source.nonce, nonce.uint64 != nil else { throw FundingPreflightError.pendingTransaction }
        let price = try FundingQuantity(rpc: checks[2].text())
        let maxPrice = try CCTPSourceGasBudget.feePerGas(gasPrice: price, baseFee: source.block.baseFee)
        let transaction: FundingRPCValue = .object([
            "from": .string(plan.owner), "to": .string(CCTPArbitrumRoute.extensionAddress),
            "data": .string(FundingHex.encode(data)), "value": .string("0x0"), "nonce": .string(nonce.rpc),
            "maxFeePerGas": .string(maxPrice.rpc), "maxPriorityFeePerGas": .string("0x0")
        ])
        // Estimate first: an eth_call with fee fields but no gas uses the node's huge default gas cap.
        let estimates = try await read([.init(.estimate, [transaction, .string(source.block.number.rpc)])])
        let gas = try FundingQuantity(rpc: estimates[0].text())
        let budget = try CCTPSourceGasBudget(estimatedGas: gas, gasPrice: price, baseFee: source.block.baseFee)
        guard source.eth >= budget.maximumNetworkFee else { throw FundingPreflightError.insufficientETH }
        guard case .object(var bounded) = transaction else { throw FundingPreflightError.invalidResponse }
        bounded["gas"] = .string(budget.gasLimit.rpc)
        let simulation = try await read([.init(.call, [.object(bounded), source.block.reference])])
        guard try simulation[0].text() == "0x" else { throw FundingPreflightError.simulationFailed }
        try await verifyCanonical(source.block)
        let pending = try await read([.init(.nonce, [.string(plan.owner), .string("pending")])])
        guard try FundingQuantity(rpc: pending[0].text()) == nonce else { throw FundingPreflightError.pendingTransaction }
        let result = CCTPSourcePreflight(plan: plan, source: source, authorization: authorization, callData: data, nonce: nonce,
            estimatedGas: gas, gasLimit: budget.gasLimit, gasPrice: price, maximumFeePerGas: budget.maximumFeePerGas,
            maximumNetworkFee: budget.maximumNetworkFee, checkedAt: clock())
        try result.validate(wallet: wallet, now: clock())
        return result
    }

    private func verifyChain() async throws {
        let results = try await read([.init(.chainID)])
        guard try FundingQuantity(rpc: results[0].text()) == FundingQuantity(UInt64(ArbitrumDepositPolicy.chainID)) else {
            throw FundingPreflightError.wrongChain
        }
    }

    private func verifyCanonical(_ block: ArbitrumFundingBlock) async throws {
        let results = try await read([.init(.chainID), .init(.block, [.string(block.number.rpc), .bool(false)])])
        guard try FundingQuantity(rpc: results[0].text()) == FundingQuantity(UInt64(ArbitrumDepositPolicy.chainID)) else {
            throw FundingPreflightError.wrongChain
        }
        let current = try ArbitrumFundingBlock(results[1], now: clock())
        guard current == block else { throw FundingPreflightError.staleState }
    }

    private func read(_ requests: [FundingRPCRequest]) async throws -> [FundingRPCValue] {
        try Task.checkCancellation()
        let values = try await rpc.read(requests)
        try Task.checkCancellation()
        guard values.count == requests.count else { throw FundingPreflightError.invalidResponse }
        return values
    }
}
