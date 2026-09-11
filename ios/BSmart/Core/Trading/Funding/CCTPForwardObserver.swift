import Foundation

struct CCTPForwardObserver: CCTPForwardObserving {
    private let rpc: FundingRPCProviding
    private let clock: @Sendable () -> Date

    init(rpc: FundingRPCProviding = HyperEVMFundingRPC(), clock: @escaping @Sendable () -> Date = { Date() }) {
        self.rpc = rpc
        self.clock = clock
    }

    func observe(_ lookup: CCTPForwardLookup, wallet: DeviceWalletSummary) async throws -> CCTPForwardObservation {
        do {
            try lookup.record.intent.require(wallet: wallet)
            let proof = try lookup.validate(at: clock())
            guard let hash = lookup.attestation.forwardHash else { throw FundingObservationError.invalidEvidence }
            try await checkChain()
            let headRequest = FundingRPCRequest(.block, [.string("latest"), .bool(false)])
            let before = try FundingSourceBlock(await one(headRequest), now: clock(), fresh: true)
            let receiptRequest = FundingRPCRequest(.receipt, [.string(hash)])
            let raw = try await one(receiptRequest)
            let receipt = try raw == .null ? nil : CCTPForwardReceipt.decode(raw, hash: hash, proof: proof, intent: lookup.record.intent)
            var blockRequest: FundingRPCRequest?
            var block: FundingSourceBlock?
            if let receipt {
                let request = FundingRPCRequest(.block, [.string(FundingQuantity(receipt.location.blockNumber).rpc), .bool(false)])
                blockRequest = request
                block = try FundingSourceBlock(await one(request), now: clock())
            }
            let nonceRequest = FundingRPCRequest(.call, [.object([
                "to": .string(CCTPArbitrumRoute.messageTransmitter),
                "data": .string(try CCTPSourceReadCodec.call("usedNonces(bytes32)", words: [proof.nonce]))]), .string("latest")])
            let used = try CCTPSourceReadCodec.boolean(await one(nonceRequest))
            var checks = [receiptRequest, headRequest]
            if let blockRequest { checks.append(blockRequest) }
            let final = try await rpc.read(checks)
            guard final.count == checks.count, final[0] == raw else { throw FundingObservationError.inconsistentState }
            let after = try FundingSourceBlock(final[1], now: clock(), fresh: true)
            guard before == after else { throw FundingObservationError.inconsistentState }
            if let block, try FundingSourceBlock(final[2], now: clock()) != block { throw FundingObservationError.inconsistentState }
            try await checkChain()
            let result = CCTPForwardObservation(id: UUID(), intentID: lookup.record.intent.id,
                sourceObservationID: lookup.source.id, attestationID: lookup.attestation.id, previousID: lookup.previous?.id,
                transactionHash: hash, head: after, nonceUsed: used, receipt: receipt, receiptBlock: block, observedAt: clock())
            try result.validate(lookup)
            return result
        } catch is CancellationError { throw CancellationError() }
        catch { throw FundingObservationError.unavailable }
    }

    private func one(_ request: FundingRPCRequest) async throws -> FundingRPCValue {
        let values = try await rpc.read([request])
        guard values.count == 1 else { throw FundingObservationError.invalidEvidence }
        return values[0]
    }

    private func checkChain() async throws {
        guard try FundingQuantity(rpc: await one(.init(.chainID)).text()) == FundingQuantity(999) else {
            throw FundingObservationError.invalidEvidence
        }
    }
}
