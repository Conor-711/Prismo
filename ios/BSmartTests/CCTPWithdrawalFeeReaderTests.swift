import XCTest
@testable import BSmart

final class CCTPWithdrawalFeeReaderTests: XCTestCase {
    func testQueriesLiveConfigurationWithoutHardcodedForwardingFee() async throws {
        let clock = TradingCheckClock(), rpc = WithdrawalFeeRPC()
        let snapshot = try await reader(rpc, clock).snapshot()
        XCTAssertEqual(snapshot.maximumCCTPFee, FundingQuantity(1_230_000))
        try snapshot.validate(now: clock.now, continuousNow: clock.instant)
        let requests = await rpc.batches
        XCTAssertEqual(requests.count, 4)
        XCTAssertEqual(requests[0][0].method, .chainID)
        XCTAssertEqual(requests[1][0].method, .block)
        XCTAssertEqual(requests[3][0].method, .chainID)
        XCTAssertEqual(requests[3][1].params, [.string("0x1f4"), .bool(false)])
        XCTAssertEqual(requests[3][2].params, [.string("latest"), .bool(false)])
        let feeCall = requests[2][5]
        XCTAssertEqual(feeCall.method, .call)
        let fields = try FundingReceiptCodec.fields(feeCall.params[0])
        XCTAssertEqual(fields["to"], .string(CCTPArbitrumRoute.coreDepositWallet))
        XCTAssertEqual(fields["data"], .string(try CCTPSourceReadCodec.call("calculateCrossChainWithdrawalFee(bool,uint32)",
            words: [FundingQuantity(1).abi, FundingQuantity(3).abi])))
        XCTAssertTrue(requests[2].allSatisfy { $0.params.last == snapshot.head.reference })
    }

    func testNormalBlockProductionPreservesPinnedConfiguration() async throws {
        let clock = TradingCheckClock()
        let rpc = WithdrawalFeeRPC(overrides: ["after": FundingObservationFixture.block(501, time: clock.now)])
        let snapshot = try await reader(rpc, clock).snapshot()
        XCTAssertEqual(snapshot.head.number, 500)
    }

    func testWrongChainRoutePausedMissingCodeOrExcessiveCapNeverProduceQuote() async throws {
        for (key, value): (String, FundingRPCValue) in [
            ("chain", .string("0xa4b1")), ("finalChain", .string("0xa4b1")), ("code", .string("0x")),
            ("token", .string(FundingQuantity(0).abi)), ("messenger", .string(FundingQuantity(0).abi)),
            ("system", .string(FundingQuantity(0).abi)), ("paused", .string(FundingQuantity(1).abi)),
            ("paused", .string(FundingQuantity(2).abi)), ("domain", .string(FundingQuantity(3).abi)),
            ("transmitter", .string(FundingQuantity(0).abi)), ("remote", .string(FundingQuantity(0).abi)),
            ("fee", .string(FundingQuantity(100_000_001).abi)), ("fee", .integer(123)),
            ("after", FundingObservationFixture.block(499, time: HyperliquidTradingFixture.now)),
            ("after", FundingObservationFixture.block(500, time: HyperliquidTradingFixture.now, reorg: true)),
            ("canonical", FundingObservationFixture.block(500, time: HyperliquidTradingFixture.now, reorg: true)),
            ("before", FundingObservationFixture.block(500, time: HyperliquidTradingFixture.now.addingTimeInterval(-31)))
        ] {
            await expectJournalFailure { try await self.reader(WithdrawalFeeRPC(overrides: [key: value]), TradingCheckClock()).snapshot() }
        }
    }

    func testDeadlineUsesBothClocksAndCannotBeExtendedByRollback() async throws {
        let clock = TradingCheckClock()
        let snapshot = try await reader(WithdrawalFeeRPC(), clock).snapshot()
        clock.advance(steady: .seconds(30))
        XCTAssertThrowsError(try snapshot.validate(now: clock.now, continuousNow: clock.instant))
        XCTAssertThrowsError(try snapshot.validate(now: clock.now.addingTimeInterval(-1), continuousNow: snapshot.checkedContinuousAt))
        XCTAssertThrowsError(try snapshot.validate(now: clock.now.addingTimeInterval(30), continuousNow: snapshot.checkedContinuousAt))
        XCTAssertThrowsError(try snapshot.validate(now: clock.now, continuousNow: snapshot.requestedContinuousAt.advanced(by: .seconds(-1))))
    }

    func testDelayedAndCancelledRequestsNeverReturnFreshSnapshot() async throws {
        let clock = TradingCheckClock()
        let rpc = WithdrawalFeeRPC(onRead: { batch in if batch == 3 { clock.advance(steady: .seconds(31)) } })
        await expectJournalFailure { try await self.reader(rpc, clock).snapshot() }
        let cancelled = Task { () throws -> CCTPWithdrawalFeeSnapshot in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await self.reader(WithdrawalFeeRPC(), TradingCheckClock()).snapshot()
        }
        await expectJournalFailure { try await cancelled.value }
    }

    private func reader(_ rpc: WithdrawalFeeRPC, _ clock: TradingCheckClock) -> CCTPWithdrawalFeeReader {
        .init(rpc: rpc, clock: { clock.now }, continuousClock: { clock.instant })
    }
}

private actor WithdrawalFeeRPC: FundingRPCProviding {
    let overrides: [String: FundingRPCValue]
    let onRead: @Sendable (Int) -> Void
    private(set) var batches: [[FundingRPCRequest]] = []

    init(overrides: [String: FundingRPCValue] = [:], onRead: @escaping @Sendable (Int) -> Void = { _ in }) {
        self.overrides = overrides; self.onRead = onRead
    }

    func read(_ requests: [FundingRPCRequest]) async throws -> [FundingRPCValue] {
        batches.append(requests); onRead(batches.count)
        if requests.count == 3 {
            return [overrides["finalChain"] ?? .string("0x3e7"),
                    overrides["canonical"] ?? FundingObservationFixture.block(500, time: HyperliquidTradingFixture.now),
                    overrides["after"] ?? FundingObservationFixture.block(500, time: HyperliquidTradingFixture.now)]
        }
        if requests[0].method == .chainID {
            return [overrides["chain"] ?? .string("0x3e7")]
        }
        if requests[0].method == .block {
            return [overrides["before"] ?? FundingObservationFixture.block(500, time: HyperliquidTradingFixture.now)]
        }
        let defaults: [(String, FundingRPCValue)] = try [
            ("code", .string("0x60006000")),
            ("token", .string(CCTPSourceReadCodec.addressWord(CCTPArbitrumRoute.destinationUSDC))),
            ("messenger", .string(CCTPSourceReadCodec.addressWord(CCTPArbitrumRoute.tokenMessenger))),
            ("system", .string(CCTPSourceReadCodec.addressWord(CCTPArbitrumRoute.coreTokenSystemAddress))),
            ("paused", .string(FundingQuantity(0).abi)), ("fee", .string(FundingQuantity(1_230_000).abi)),
            ("domain", .string(FundingQuantity(19).abi)),
            ("transmitter", .string(CCTPSourceReadCodec.addressWord(CCTPArbitrumRoute.messageTransmitter))),
            ("remote", .string(CCTPSourceReadCodec.addressWord(CCTPArbitrumRoute.tokenMessenger)))
        ]
        guard requests.count == defaults.count else { throw HyperliquidWithdrawalError.invalidResponse }
        return defaults.map { overrides[$0.0] ?? $0.1 }
    }
}
