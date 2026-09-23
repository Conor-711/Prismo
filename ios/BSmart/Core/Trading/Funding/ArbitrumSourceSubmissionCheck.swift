import Foundation

protocol CCTPSourceSubmissionChecking: Sendable {
    func check(signed: CCTPSignedSourceTransaction, wallet: DeviceWalletSummary) async throws -> FundingSubmissionCheck
}

struct FundingSubmissionCheck: Sendable {
    let checkedAt: Date
    let expiresAt: Date
    private let hash: String
    private let accountID: UUID
    private let owner: String

    fileprivate init(signed: CCTPSignedSourceTransaction, checkedAt: Date, sourceExpiry: Date) {
        hash = signed.hash
        accountID = signed.transaction.preflight.plan.accountID
        owner = signed.transaction.preflight.plan.owner
        self.checkedAt = checkedAt
        expiresAt = min(checkedAt.addingTimeInterval(10), sourceExpiry, signed.transaction.preflight.expiresAt)
    }

    func validate(hash: String, wallet: DeviceWalletSummary, now: Date) throws {
        guard self.hash == hash, accountID == wallet.accountID, owner == wallet.address,
              wallet.canAuthorizeTransactions else { throw FundingJournalError.conflict }
        guard now >= checkedAt, now < expiresAt else { throw FundingJournalError.expired }
    }
}

struct ArbitrumSourceSubmissionCheck: CCTPSourceSubmissionChecking {
    private let rpc: ArbitrumFundingRPCProviding
    private let clock: @Sendable () -> Date

    init(rpc: ArbitrumFundingRPCProviding = ArbitrumFundingRPC(), clock: @escaping @Sendable () -> Date = { Date() }) {
        self.rpc = rpc
        self.clock = clock
    }

    func check(signed: CCTPSignedSourceTransaction, wallet: DeviceWalletSummary) async throws -> FundingSubmissionCheck {
        let original = signed.transaction.preflight
        try original.validate(wallet: wallet, now: clock())
        let fresh = try await ArbitrumSourcePreflight(rpc: rpc, clock: clock).prepare(
            plan: original.plan, wallet: wallet, authorization: original.authorization)
        try original.validate(wallet: wallet, now: clock())
        guard fresh.source.block.number >= original.source.block.number,
              fresh.source.block.number != original.source.block.number || fresh.source.block.hash == original.source.block.hash else {
            throw FundingPreflightError.staleState
        }
        guard fresh.nonce == original.nonce else { throw FundingPreflightError.pendingTransaction }
        guard fresh.callData == original.callData,
              fresh.source.observedCodeHashes == original.source.observedCodeHashes else { throw FundingPreflightError.routeChanged }
        // The approved limit already includes headroom. Consume that headroom instead of buffering twice.
        guard fresh.estimatedGas <= original.gasLimit,
              max(fresh.gasPrice, fresh.source.block.baseFee) <= original.maximumFeePerGas else { throw FundingPreflightError.feeQuoteChanged }
        guard fresh.source.eth >= original.maximumNetworkFee else { throw FundingPreflightError.insufficientETH }

        // Re-simulate with the APPROVED limits, not the newly estimated envelope; never bump fees silently.
        let transaction: FundingRPCValue = .object([
            "from": .string(wallet.address), "to": .string(CCTPArbitrumRoute.extensionAddress),
            "type": .string("0x2"), "chainId": .string(FundingQuantity(UInt64(ArbitrumDepositPolicy.chainID)).rpc),
            "data": .string(FundingHex.encode(original.callData)), "value": .string("0x0"),
            "nonce": .string(original.nonce.rpc), "gas": .string(original.gasLimit.rpc),
            "maxFeePerGas": .string(original.maximumFeePerGas.rpc), "maxPriorityFeePerGas": .string("0x0")
        ])
        let results = try await read([
            .init(.call, [transaction, fresh.source.block.reference]),
            .init(.estimate, [transaction, .string(fresh.source.block.number.rpc)])
        ])
        guard try results[0].text() == "0x" else { throw FundingPreflightError.simulationFailed }
        let gas = try FundingQuantity(rpc: results[1].text())
        guard gas >= FundingQuantity(21_000),
              gas <= original.gasLimit else { throw FundingPreflightError.feeQuoteChanged }
        let final = try await read([
            .init(.chainID), .init(.block, [.string(fresh.source.block.number.rpc), .bool(false)]),
            .init(.nonce, [.string(wallet.address), .string("pending")])
        ])
        guard try FundingQuantity(rpc: final[0].text()) == FundingQuantity(UInt64(ArbitrumDepositPolicy.chainID)) else {
            throw FundingPreflightError.wrongChain
        }
        guard try ArbitrumFundingBlock(final[1], now: clock()) == fresh.source.block else { throw FundingPreflightError.staleState }
        guard try FundingQuantity(rpc: final[2].text()) == original.nonce else { throw FundingPreflightError.pendingTransaction }
        try original.validate(wallet: wallet, now: clock())
        try fresh.validate(wallet: wallet, now: clock())
        let check = FundingSubmissionCheck(signed: signed, checkedAt: clock(), sourceExpiry: fresh.expiresAt)
        try check.validate(hash: signed.hash, wallet: wallet, now: clock())
        return check
    }

    private func read(_ requests: [FundingRPCRequest]) async throws -> [FundingRPCValue] {
        try Task.checkCancellation()
        let values = try await rpc.read(requests)
        try Task.checkCancellation()
        guard values.count == requests.count else { throw FundingPreflightError.invalidResponse }
        return values
    }
}
