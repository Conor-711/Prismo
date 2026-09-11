import Foundation

// This is the CCTP contract cap only, not total fees or a withdrawal authorization.
struct CCTPWithdrawalFeeSnapshot: Sendable {
    let head: FundingSourceBlock
    let contractCodeHash: String
    let maximumCCTPFee: FundingQuantity
    let requestedAt: Date
    let checkedAt: Date
    let requestedContinuousAt: ContinuousClock.Instant
    let checkedContinuousAt: ContinuousClock.Instant

    func validate(now: Date, continuousNow: ContinuousClock.Instant = .now) throws {
        let age = now.timeIntervalSince(requestedAt)
        guard requestedAt.timeIntervalSince1970.isFinite, age.isFinite, age >= 0, age < 30,
              checkedAt >= requestedAt, now >= checkedAt,
              checkedContinuousAt >= requestedContinuousAt, continuousNow >= checkedContinuousAt,
              requestedContinuousAt.duration(to: continuousNow) < .seconds(30),
              FundingHex.decode(contractCodeHash)?.count == 32,
              maximumCCTPFee <= FundingQuantity(100_000_000) else { throw HyperliquidWithdrawalError.stale }
        try head.validate(now: now, fresh: true)
        guard now.timeIntervalSince(head.timestamp) < 30 else { throw HyperliquidWithdrawalError.stale }
    }
}

protocol CCTPWithdrawalFeeReading: Sendable {
    func snapshot() async throws -> CCTPWithdrawalFeeSnapshot
}

struct CCTPWithdrawalFeeReader: CCTPWithdrawalFeeReading {
    private let rpc: any FundingRPCProviding
    private let clock: @Sendable () -> Date
    private let continuousClock: @Sendable () -> ContinuousClock.Instant

    init(rpc: any FundingRPCProviding = HyperEVMFundingRPC(), clock: @escaping @Sendable () -> Date = { Date() },
         continuousClock: @escaping @Sendable () -> ContinuousClock.Instant = { .now }) {
        self.rpc = rpc; self.clock = clock; self.continuousClock = continuousClock
    }

    func snapshot() async throws -> CCTPWithdrawalFeeSnapshot {
        let start = clock(), steady = continuousClock()
        do {
            try Task.checkCancellation()
            try await checkChain()
            let before = try await head()
            // Use one canonical EIP-1898 state; normal block production must not invalidate the read.
            let requests = try [FundingRPCRequest(.code, [.string(CCTPArbitrumRoute.coreDepositWallet), before.reference]),
                call("token()", block: before), call("tokenMessenger()", block: before),
                call("tokenSystemAddress()", block: before), call("paused()", block: before),
                call("calculateCrossChainWithdrawalFee(bool,uint32)", block: before, words: [FundingQuantity(1).abi, FundingQuantity(3).abi]),
                call("localDomain()", block: before, address: CCTPArbitrumRoute.messageTransmitter),
                call("localMessageTransmitter()", block: before, address: CCTPArbitrumRoute.tokenMessenger),
                call("remoteTokenMessengers(uint32)", block: before, words: [FundingQuantity(3).abi], address: CCTPArbitrumRoute.tokenMessenger)]
            let values = try await rpc.read(requests)
            guard values.count == requests.count else { throw HyperliquidWithdrawalError.invalidResponse }
            let final = try await rpc.read([.init(.chainID), .init(.block, [.string(before.rpc), .bool(false)]),
                                           .init(.block, [.string("latest"), .bool(false)])])
            try Task.checkCancellation()
            guard final.count == 3, try FundingQuantity(rpc: final[0].text()) == FundingQuantity(999) else {
                throw HyperliquidWithdrawalError.routeChanged
            }
            let canonical = try FundingSourceBlock(final[1], now: clock(), fresh: true)
            let after = try FundingSourceBlock(final[2], now: clock(), fresh: true)
            guard before == canonical, after.number >= before.number, after.timestamp >= before.timestamp,
                  after.number != before.number || after == before else { throw HyperliquidWithdrawalError.stale }
            guard try values[1].text() == CCTPSourceReadCodec.addressWord(CCTPArbitrumRoute.destinationUSDC),
                  try values[2].text() == CCTPSourceReadCodec.addressWord(CCTPArbitrumRoute.tokenMessenger),
                  try values[3].text() == CCTPSourceReadCodec.addressWord(CCTPArbitrumRoute.coreTokenSystemAddress),
                  try !CCTPSourceReadCodec.boolean(values[4]),
                  try FundingQuantity(abi: values[6].text()) == FundingQuantity(19),
                  try values[7].text() == CCTPSourceReadCodec.addressWord(CCTPArbitrumRoute.messageTransmitter),
                  try values[8].text() == CCTPSourceReadCodec.addressWord(CCTPArbitrumRoute.tokenMessenger) else {
                throw HyperliquidWithdrawalError.routeChanged
            }
            let snapshot = try CCTPWithdrawalFeeSnapshot(head: before, contractCodeHash: CCTPSourceReadCodec.codeHash(values[0]),
                maximumCCTPFee: FundingQuantity(abi: values[5].text()), requestedAt: start, checkedAt: clock(),
                requestedContinuousAt: steady, checkedContinuousAt: continuousClock())
            try snapshot.validate(now: clock(), continuousNow: continuousClock())
            return snapshot
        } catch is CancellationError { throw CancellationError() }
        catch let error as HyperliquidWithdrawalError { throw error }
        catch { throw HyperliquidWithdrawalError.unavailable }
    }

    private func checkChain() async throws {
        let values = try await rpc.read([.init(.chainID)])
        guard values.count == 1, try FundingQuantity(rpc: values[0].text()) == FundingQuantity(999) else {
            throw HyperliquidWithdrawalError.routeChanged
        }
    }

    private func head() async throws -> FundingSourceBlock {
        let values = try await rpc.read([.init(.block, [.string("latest"), .bool(false)])])
        guard values.count == 1 else { throw HyperliquidWithdrawalError.invalidResponse }
        return try .init(values[0], now: clock(), fresh: true)
    }

    private func call(_ signature: String, block: FundingSourceBlock, words: [String] = [],
                      address: String = CCTPArbitrumRoute.coreDepositWallet) throws -> FundingRPCRequest {
        .init(.call, [.object(["to": .string(address), "data": .string(try CCTPSourceReadCodec.call(signature, words: words))]), block.reference])
    }
}
