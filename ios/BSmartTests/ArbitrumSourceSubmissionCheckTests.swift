import XCTest
@testable import BSmart

final class ArbitrumSourceSubmissionCheckTests: XCTestCase {
    func testRechecksExactApprovedEnvelopeAndKeepsOriginalDeadline() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let signed = try await context.signed(context.transaction())
        context.clock.advance(5)
        let rpc = try PreflightStubRPC(blockTime: context.clock.now)
        let service = ArbitrumSourceSubmissionCheck(rpc: rpc, clock: { context.clock.now })
        let check = try await service.check(signed: signed, wallet: context.wallet)
        XCTAssertEqual(check.checkedAt, context.clock.now)
        XCTAssertEqual(check.expiresAt, context.clock.now.addingTimeInterval(10))
        let requests = await rpc.requests
        let capped = try XCTUnwrap(requests.last(where: { $0.method == .estimate }))
        guard case .object(let fields) = capped.params.first else { return XCTFail("Missing fixed call") }
        XCTAssertEqual(fields["gas"], .string(signed.transaction.preflight.gasLimit.rpc))
        XCTAssertEqual(fields["maxFeePerGas"], .string(signed.transaction.preflight.maximumFeePerGas.rpc))
        XCTAssertEqual(fields["maxPriorityFeePerGas"], .string("0x0"))
        XCTAssertEqual(fields["data"], .string(FundingHex.encode(signed.transaction.preflight.callData)))
        XCTAssertEqual(fields["nonce"], .string("0x0"))
        XCTAssertEqual(fields["chainId"], .string("0xa4b1"))
        XCTAssertEqual(fields["value"], .string("0x0"))
        XCTAssertEqual(fields["to"], .string(CCTPArbitrumRoute.extensionAddress))
        try check.validate(hash: signed.hash, wallet: context.wallet, now: context.clock.now)
        XCTAssertThrowsError(try check.validate(hash: signed.hash, wallet: context.wallet, now: check.expiresAt))
        XCTAssertThrowsError(try check.validate(hash: signed.hash, wallet: context.wallet, now: check.checkedAt.addingTimeInterval(-1)))

        context.clock.advance(20)
        let later = try await ArbitrumSourceSubmissionCheck(rpc: PreflightStubRPC(blockTime: context.clock.now),
            clock: { context.clock.now }).check(signed: signed, wallet: context.wallet)
        XCTAssertEqual(later.expiresAt, signed.transaction.preflight.expiresAt)
    }

    func testStateChangesStopBeforeAnyPermissionOrFeeBump() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let signed = try await context.signed(context.transaction())
        for overrides in [
            ["pendingNonce": .string("0x1")],
            ["nonce": .string("0x1"), "pendingNonce": .string("0x1")],
            ["authorization": .string(FundingQuantity(1).abi)],
            ["usdc": .string(FundingQuantity(1).abi)],
            ["eth": .string("0x1")],
            ["gasPrice": .string(FundingQuantity(21_000_000).rpc)],
            ["gas": .string(FundingQuantity(200_001).rpc)],
            [CCTPArbitrumRoute.extensionAddress: .string("0x6002600055")],
            ["simulation": .string("0x01")]
        ] as [[String: FundingRPCValue]] {
            let service = ArbitrumSourceSubmissionCheck(rpc: try PreflightStubRPC(overrides: overrides), clock: { context.clock.now })
            await expectJournalFailure { try await service.check(signed: signed, wallet: context.wallet) }
        }
    }

    func testNewStateCannotRenewExpiredSignatureOrCrossAccountOrHash() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let signed = try await context.signed(context.transaction())
        let check = try await context.recordedSubmissionCheck(signed)
        let other = DeviceWalletSummary(accountID: UUID(), address: context.wallet.address, recoveryVerified: true)
        XCTAssertThrowsError(try check.validate(hash: signed.hash, wallet: other, now: context.clock.now))
        XCTAssertThrowsError(try check.validate(hash: "0x" + String(repeating: "ab", count: 32), wallet: context.wallet, now: context.clock.now))
        context.clock.advance(30)
        let rpc = try PreflightStubRPC(blockTime: context.clock.now)
        await expectJournalFailure {
            try await ArbitrumSourceSubmissionCheck(rpc: rpc, clock: { context.clock.now }).check(signed: signed, wallet: context.wallet)
        }
        let requests = await rpc.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testFinalNonceReorgAndCappedSimulationAreCheckedAfterFreshPreflight() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let signed = try await context.signed(context.transaction())
        for mode in SubmissionCheckRPC.Mode.allCases {
            let rpc = try SubmissionCheckRPC(mode: mode)
            await expectJournalFailure {
                try await ArbitrumSourceSubmissionCheck(rpc: rpc, clock: { context.clock.now }).check(signed: signed, wallet: context.wallet)
            }
            let reached = await rpc.reachedTarget
            XCTAssertTrue(reached, "Did not exercise post-preflight check: \(mode)")
        }
    }

    func testExpiredCheckCannotIssuePermitAndExpiryDuringCommitCannotEscape() async throws {
        for duringCommit in [false, true] {
            let context = FundingJournalTestContext(); defer { context.cleanup() }
            let journal = try context.journal()
            let transaction = try await context.transaction()
            let id = UUID()
            let signed = try await context.ready(transaction, id: id, journal: journal)
            let check = try await context.recordedSubmissionCheck(signed)
            let delayed = try context.journal { phase in
                if duringCommit && phase == .afterCommit { context.clock.advance(10) }
            }
            if !duringCommit { context.clock.advance(10) }
            await expectJournalFailure { try await delayed.beginSubmission(id: id, signed: signed, wallet: context.wallet, check: check) }
            let records = try await journal.records(wallet: context.wallet)
            XCTAssertEqual(records.first?.state, duringCommit ? .submitting : .signed)
        }
    }
}

private actor SubmissionCheckRPC: ArbitrumFundingRPCProviding {
    enum Mode: CaseIterable { case nonce, reorg, wrongChain, simulation, estimate, olderHead, newHashAtSameHeight }
    let mode: Mode
    let base: PreflightStubRPC
    private(set) var reachedTarget = false
    init(mode: Mode) throws { self.mode = mode; base = try PreflightStubRPC() }
    func read(_ requests: [FundingRPCRequest]) async throws -> [FundingRPCValue] {
        var values = try await base.read(requests)
        for index in requests.indices where requests[index].method == .block {
            if case .object(var fields) = values[index] {
                if mode == .olderHead { fields["number"] = .string("0x1233"); reachedTarget = true }
                if mode == .newHashAtSameHeight { fields["hash"] = .string("0x" + String(repeating: "22", count: 32)); reachedTarget = true }
                values[index] = .object(fields)
            }
        }
        if requests.count == 3, requests[0].method == .chainID {
            switch mode {
            case .nonce: values[2] = .string("0x1")
            case .reorg: values[1] = PreflightTestFixture.block(reorg: true)
            case .wrongChain: values[0] = .string("0x1")
            default: return values
            }
            reachedTarget = true
        }
        if requests.count == 2, requests[1].method == .estimate {
            if mode == .simulation { values[0] = .string("0x01"); reachedTarget = true }
            if mode == .estimate { values[1] = .string(FundingQuantity(200_001).rpc); reachedTarget = true }
        }
        return values
    }
}
