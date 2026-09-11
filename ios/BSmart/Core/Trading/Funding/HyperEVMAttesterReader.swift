import Foundation

struct CCTPVerifierSnapshot: Codable, Equatable, Sendable {
    let head: FundingSourceBlock
    let transmitterCodeHash: String
    let threshold: UInt64
    let enabledSigners: [String]
    let paused: Bool
    let nonceUsed: Bool

    func validate(proof: CCTPAttestedMessage, at date: Date) throws {
        try head.validate(now: date, fresh: true)
        guard FundingHex.decode(transmitterCodeHash)?.count == 32, transmitterCodeHash != FundingQuantity(0).abi,
              (1...16).contains(threshold),
              threshold == enabledSigners.count, try enabledSigners == proof.signers() else {
            throw FundingObservationError.invalidEvidence
        }
    }
}

protocol CCTPVerifierReading: Sendable {
    func snapshot(proof: CCTPAttestedMessage) async throws -> CCTPVerifierSnapshot
}

struct HyperEVMAttesterReader: CCTPVerifierReading {
    private let rpc: FundingRPCProviding
    private let clock: @Sendable () -> Date

    init(rpc: FundingRPCProviding = HyperEVMFundingRPC(), clock: @escaping @Sendable () -> Date = { Date() }) {
        self.rpc = rpc
        self.clock = clock
    }

    func snapshot(proof: CCTPAttestedMessage) async throws -> CCTPVerifierSnapshot {
        do {
            let signers = try proof.signers()
            try await checkChain()
            let before = try await head()
            var requests = [FundingRPCRequest(.code, [.string(CCTPArbitrumRoute.messageTransmitter), .string("latest")])]
            requests += try ["localDomain()", "version()", "signatureThreshold()", "paused()"].map { try call($0) }
            requests.append(try call("usedNonces(bytes32)", words: [proof.nonce]))
            requests += try signers.map { try call("isEnabledAttester(address)", words: [CCTPSourceReadCodec.addressWord($0)]) }
            let values = try await rpc.read(requests)
            guard values.count == requests.count else { throw FundingObservationError.invalidEvidence }
            // HyperEVM's public RPC supports latest contract state only, not EIP-1898.
            let after = try await head()
            try await checkChain()
            guard before == after else { throw FundingObservationError.inconsistentState }
            guard try FundingQuantity(abi: values[1].text()) == FundingQuantity(19),
                  try FundingQuantity(abi: values[2].text()) == FundingQuantity(1),
                  try values.dropFirst(6).allSatisfy({ try CCTPSourceReadCodec.boolean($0) }) else {
                throw FundingObservationError.invalidEvidence
            }
            let result = try CCTPVerifierSnapshot(
                head: after, transmitterCodeHash: CCTPSourceReadCodec.codeHash(values[0]),
                threshold: FundingQuantity(abi: values[3].text()).uint64Checked(), enabledSigners: signers,
                paused: CCTPSourceReadCodec.boolean(values[4]), nonceUsed: CCTPSourceReadCodec.boolean(values[5]))
            try result.validate(proof: proof, at: clock())
            return result
        } catch is CancellationError { throw CancellationError() }
        catch { throw FundingObservationError.unavailable }
    }

    private func head() async throws -> FundingSourceBlock {
        let values = try await rpc.read([.init(.block, [.string("latest"), .bool(false)])])
        guard values.count == 1 else { throw FundingObservationError.invalidEvidence }
        return try FundingSourceBlock(values[0], now: clock(), fresh: true)
    }

    private func checkChain() async throws {
        let values = try await rpc.read([.init(.chainID)])
        guard values.count == 1, try FundingQuantity(rpc: values[0].text()) == FundingQuantity(999) else {
            throw FundingObservationError.invalidEvidence
        }
    }

    private func call(_ signature: String, words: [String] = []) throws -> FundingRPCRequest {
        .init(.call, [.object(["to": .string(CCTPArbitrumRoute.messageTransmitter),
                              "data": .string(try CCTPSourceReadCodec.call(signature, words: words))]), .string("latest")])
    }
}
