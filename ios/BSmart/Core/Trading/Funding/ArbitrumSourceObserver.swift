import Foundation

protocol FundingSourceObserving: Sendable {
    func observe(_ lookup: FundingSourceLookup, wallet: DeviceWalletSummary) async throws -> FundingSourceObservation
}

struct ArbitrumSourceObserver: FundingSourceObserving {
    private let rpc: ArbitrumFundingRPCProviding
    private let clock: @Sendable () -> Date
    init(rpc: ArbitrumFundingRPCProviding = ArbitrumFundingRPC(), clock: @escaping @Sendable () -> Date = { Date() }) {
        self.rpc = rpc
        self.clock = clock
    }

    func observe(_ lookup: FundingSourceLookup, wallet: DeviceWalletSummary) async throws -> FundingSourceObservation {
        do { return try await checked(lookup, wallet: wallet) }
        catch is CancellationError { throw CancellationError() }
        catch let error as FundingObservationError { throw error }
        catch { throw FundingObservationError.unavailable }
    }

    private func checked(_ lookup: FundingSourceLookup, wallet: DeviceWalletSummary) async throws -> FundingSourceObservation {
        let record = lookup.record
        try record.intent.require(wallet: wallet)
        try CCTPSourceTransaction.verifyStored(intent: record.intent, signed: record.signed)
        guard let signed = record.signed, record.needsReconciliation else { throw FundingObservationError.invalidEvidence }
        let chain = try await read([.init(.chainID)])
        try verifyChain(chain[0])
        let transactionRequest = FundingRPCRequest(.transaction, [.string(signed.hash)])
        let receiptRequest = FundingRPCRequest(.receipt, [.string(signed.hash)])
        let initial = try await read([.init(.block, [.string("latest"), .bool(false)]), transactionRequest, receiptRequest])
        let head = try FundingSourceBlock(initial[0], now: clock(), fresh: true)
        let location = initial[1] == .null ? nil : try FundingReceiptCodec.transaction(initial[1], record: record)
        let receipt = initial[2] == .null ? nil : try FundingReceiptCodec.receipt(initial[2], record: record)
        guard location == receipt?.location, initial[1] != .null || receipt == nil else { throw FundingObservationError.inconsistentState }
        let authCall = try CCTPSourceReadCodec.call("authorizationState(address,bytes32)", words: [
            CCTPSourceReadCodec.addressWord(wallet.address), record.intent.authorizationNonce])
        var checks = [
            FundingRPCRequest(.nonce, [.string(wallet.address), head.reference]),
            .init(.nonce, [.string(wallet.address), .string("pending")]),
            .init(.call, [.object(["to": .string(ArbitrumDepositPolicy.nativeUSDC), "data": .string(authCall)]), head.reference]),
            .init(.block, [.string("finalized"), .bool(false)])
        ]
        if let receipt { checks.append(.init(.block, [.string(FundingQuantity(receipt.location.blockNumber).rpc), .bool(false)])) }
        if let prior = lookup.previous?.receipt { checks.append(.init(.block, [.string(FundingQuantity(prior.location.blockNumber).rpc), .bool(false)])) }
        let values = try await read(checks)
        let finalized = try FundingSourceBlock(values[3], now: clock())
        let receiptBlock = receipt == nil ? nil : try FundingSourceBlock(values[4], now: clock())
        let priorBlock = lookup.previous?.receipt == nil ? nil : try FundingSourceBlock(values.last!, now: clock())
        let blocks = [head, finalized] + [receiptBlock, priorBlock].compactMap { $0 }
        let final = try await read([.init(.chainID), transactionRequest, receiptRequest] + blocks.map {
            .init(.block, [.string($0.rpc), .bool(false)])
        })
        try verifyChain(final[0])
        guard final[1] == initial[1], final[2] == initial[2] else { throw FundingObservationError.inconsistentState }
        for (index, block) in blocks.enumerated() {
            guard try FundingSourceBlock(final[index + 3], now: clock()) == block else { throw FundingObservationError.inconsistentState }
        }
        let observation = FundingSourceObservation(id: UUID(), intentID: record.intent.id, previousID: lookup.previous?.id,
            transactionHash: signed.hash, transactionPresent: initial[1] != .null, receipt: receipt,
            head: head, finalizedHead: finalized, receiptBlock: receiptBlock, priorReceiptBlock: priorBlock,
            latestNonce: try FundingQuantity(rpc: values[0].text()).rpc,
            pendingNonce: try FundingQuantity(rpc: values[1].text()).rpc,
            authorizationUsed: try CCTPSourceReadCodec.boolean(values[2]), observedAt: clock())
        try observation.validate(record: record, previous: lookup.previous)
        return observation
    }

    private func verifyChain(_ result: FundingRPCValue) throws {
        guard try FundingQuantity(rpc: result.text()) == FundingQuantity(UInt64(ArbitrumDepositPolicy.chainID)) else {
            throw FundingObservationError.inconsistentState
        }
    }
    private func read(_ requests: [FundingRPCRequest]) async throws -> [FundingRPCValue] {
        try Task.checkCancellation()
        let values = try await rpc.read(requests)
        try Task.checkCancellation()
        guard values.count == requests.count else { throw FundingObservationError.invalidEvidence }
        return values
    }
}
