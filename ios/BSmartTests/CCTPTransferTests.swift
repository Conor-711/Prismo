import XCTest
@testable import BSmart

@MainActor
final class CCTPTransferTests: XCTestCase {
    func testFeeIncreasePastApprovedLimitAllowsNewQuoteAndConfirmation() async throws {
        let rig = try TransferTestRig(failures: TransferTestFailures(0, submissionGas: [240_001, 210_000]))
        defer { rig.fixture.context.cleanup() }
        await rig.store.prepareTransfer(amount: "2.8", wallet: rig.fixture.wallet)
        await rig.store.confirmTransfer()
        XCTAssertEqual(rig.store.display.phase, .amount)
        XCTAssertEqual(rig.store.errorMessage, FundingPreflightError.feeQuoteChanged.localizedDescription)
        XCTAssertEqual(rig.broadcast.count, 0)
        let journal = try rig.fixture.context.journal()
        let sources = try await journal.records(wallet: rig.fixture.wallet)
        let failed = try XCTUnwrap(sources.first)
        XCTAssertEqual(failed.state, .notSubmitted)
        XCTAssertNotNil(failed.signed)
        XCTAssertFalse(failed.reservesNonce)
        await rig.store.prepareTransfer(amount: "2.5", wallet: rig.fixture.wallet)
        XCTAssertEqual(rig.store.display.phase, .networkFee, rig.store.errorMessage ?? "")
        await rig.store.confirmTransfer()
        XCTAssertEqual(rig.store.display.phase, .recorded, rig.store.errorMessage ?? "")
        XCTAssertEqual(rig.broadcast.count, 1)
    }

    func testRestoreReleasesLegacySignedButNeverSubmittedAttemptWithoutDeletingEvidence() async throws {
        let rig = try TransferTestRig(); defer { rig.fixture.context.cleanup() }
        await rig.store.prepareTransfer(amount: "2.8", wallet: rig.fixture.wallet)
        await rig.store.sign()
        let journal = try rig.fixture.context.journal()
        let before = try await journal.records(wallet: rig.fixture.wallet)
        let saved = try XCTUnwrap(before.first)
        XCTAssertEqual(saved.state, .signed)
        rig.store.invalidate()
        rig.fixture.context.clock.advance(400)
        await rig.store.restore(wallet: rig.fixture.wallet)
        XCTAssertEqual(rig.store.display.phase, .amount, rig.store.errorMessage ?? "")
        let after = try await journal.records(wallet: rig.fixture.wallet)
        XCTAssertEqual(after.first?.state, .notSubmitted)
        XCTAssertEqual(after.first?.signed, saved.signed)
        XCTAssertEqual(rig.broadcast.count, 0)
    }

    func testFailedSimulationEndsAttemptAndAllowsNewDepositImmediately() async throws {
        let rig = try TransferTestRig(failures: TransferTestFailures(1)); defer { rig.fixture.context.cleanup() }
        await rig.store.prepareTransfer(amount: "2.8", wallet: rig.fixture.wallet)
        XCTAssertEqual(rig.store.display.phase, .amount)
        XCTAssertEqual(rig.store.errorMessage, FundingPreflightError.simulationFailed.localizedDescription)
        let journal = try rig.fixture.context.journal()
        let consents = try await journal.consents(wallet: rig.fixture.wallet)
        let first = try XCTUnwrap(consents.first)
        XCTAssertEqual(first.state, .notSubmitted); XCTAssertNotNil(first.signature)
        XCTAssertEqual(rig.broadcast.count, 0)
        await rig.store.prepareTransfer(amount: "2.5", wallet: rig.fixture.wallet)
        XCTAssertEqual(rig.store.display.phase, .networkFee, rig.store.errorMessage ?? "")
        XCTAssertEqual(rig.store.display.details?.amount, 2_500_000)
        await rig.store.confirmTransfer()
        XCTAssertEqual(rig.store.display.phase, .recorded, rig.store.errorMessage ?? "")
        XCTAssertEqual(rig.broadcast.count, 1)
    }

    func testLegacySavedAuthorizationFailureDoesNotTrapRecovery() async throws {
        let rig = try TransferTestRig(failures: TransferTestFailures(1)); defer { rig.fixture.context.cleanup() }
        let journal = try rig.fixture.context.journal(), id = UUID()
        _ = try await journal.beginConsent(id: id, plan: rig.fixture.plan, wallet: rig.fixture.wallet)
        let permit = try await journal.beginAuthorization(id: id, wallet: rig.fixture.wallet)
        let signature = try await rig.fixture.signer().authorizeDeposit(permit, lease: .init(wallet: rig.fixture.wallet))
        _ = try await journal.recordAuthorization(id: id, signature: signature, wallet: rig.fixture.wallet)
        await rig.store.restore(wallet: rig.fixture.wallet)
        XCTAssertEqual(rig.store.display.phase, .amount, rig.store.errorMessage ?? "")
        let history = try await journal.history(wallet: rig.fixture.wallet)
        XCTAssertEqual(history.first?.stage, .notSubmitted)
        XCTAssertEqual(history.first?.stage.requiresReconciliation, false)
        await rig.store.prepareTransfer(amount: "2.8", wallet: rig.fixture.wallet)
        XCTAssertEqual(rig.store.display.phase, .networkFee, rig.store.errorMessage ?? "")
        XCTAssertEqual(rig.broadcast.count, 0)
    }

    func testReturningFromUnsignedFeePreviewDoesNotBlockAnotherReview() async throws {
        let rig = try TransferTestRig(); defer { rig.fixture.context.cleanup() }
        await rig.store.prepareTransfer(amount: "2.8", wallet: rig.fixture.wallet)
        XCTAssertEqual(rig.store.display.phase, .networkFee)
        rig.store.invalidate()
        await rig.store.restore(wallet: rig.fixture.wallet)
        XCTAssertEqual(rig.store.display.phase, .amount, rig.store.errorMessage ?? "")
        let records = try await rig.fixture.context.journal().records(wallet: rig.fixture.wallet)
        XCTAssertEqual(records.first?.state, .cancelled)
        XCTAssertNil(records.first?.signed)
        await rig.store.prepareTransfer(amount: "2.8", wallet: rig.fixture.wallet)
        XCTAssertEqual(rig.store.display.phase, .networkFee, rig.store.errorMessage ?? "")
        XCTAssertEqual(rig.broadcast.count, 0)
    }

    func testSimplifiedTransferNeedsOnlyPrepareAndConfirm() async throws {
        let rig = try TransferTestRig(); defer { rig.fixture.context.cleanup() }
        await rig.store.prepareTransfer(amount: "2.8", wallet: rig.fixture.wallet)
        XCTAssertEqual(rig.store.display.phase, .networkFee, rig.store.errorMessage ?? "")
        XCTAssertEqual(rig.broadcast.count, 0)
        XCTAssertEqual(rig.store.display.details?.amount, 2_800_000)
        await rig.store.confirmTransfer()
        XCTAssertEqual(rig.store.display.phase, .recorded, rig.store.errorMessage ?? "")
        XCTAssertEqual(rig.broadcast.count, 1)
        await rig.store.confirmTransfer()
        XCTAssertEqual(rig.broadcast.count, 1)
    }

    func testRestoreContinuesSavedAuthorizationWithoutSigningItAgain() async throws {
        let rig = try TransferTestRig(); defer { rig.fixture.context.cleanup() }
        let journal = try rig.fixture.context.journal(), id = UUID()
        _ = try await journal.beginConsent(id: id, plan: rig.fixture.plan, wallet: rig.fixture.wallet)
        let permit = try await journal.beginAuthorization(id: id, wallet: rig.fixture.wallet)
        let signature = try await rig.fixture.signer().authorizeDeposit(permit, lease: .init(wallet: rig.fixture.wallet))
        _ = try await journal.recordAuthorization(id: id, signature: signature, wallet: rig.fixture.wallet)
        let keyReads = rig.fixture.keychain.reads
        rig.fixture.context.clock.advance(65)
        await rig.store.restore(wallet: rig.fixture.wallet)
        XCTAssertEqual(rig.store.display.phase, .networkFee, rig.store.errorMessage ?? "")
        XCTAssertEqual(rig.fixture.keychain.reads, keyReads)
        XCTAssertEqual(rig.broadcast.count, 0)
    }

    func testRestoreUnblocksExpiredOrphanAndDoesNotBroadcast() async throws {
        let rig = try TransferTestRig(); defer { rig.fixture.context.cleanup() }
        let journal = try rig.fixture.context.journal(), id = UUID()
        _ = try await journal.beginConsent(id: id, plan: rig.fixture.plan, wallet: rig.fixture.wallet)
        let permit = try await journal.beginAuthorization(id: id, wallet: rig.fixture.wallet)
        let signature = try await rig.fixture.signer().authorizeDeposit(permit, lease: .init(wallet: rig.fixture.wallet))
        _ = try await journal.recordAuthorization(id: id, signature: signature, wallet: rig.fixture.wallet)
        rig.fixture.context.clock.advance(301)
        await rig.store.restore(wallet: rig.fixture.wallet)
        XCTAssertEqual(rig.store.display.phase, .amount, rig.store.errorMessage ?? "")
        let history = try await journal.consents(wallet: rig.fixture.wallet)
        XCTAssertEqual(history.first?.state, .expired)
        XCTAssertEqual(rig.broadcast.count, 0)
    }

    func testPreparationDeniesByDefaultBeforeReadingWalletOrSigning() async throws {
        let rig = try TransferTestRig(); defer { rig.fixture.context.cleanup() }
        let preparation = CCTPDepositPreparation(service: rig.service, signer: rig.fixture.signer(),
            journal: try rig.fixture.context.journal(), preflight: rig.source)
        await preparation.review(plan: rig.fixture.plan, wallet: rig.fixture.wallet)
        XCTAssertEqual(rig.service.reads, 0)
        XCTAssertEqual(rig.fixture.keychain.reads, 0)
        XCTAssertEqual(CCTPTransferDisplay(preparation.state).phase, .amount)
    }

    func testClosedGateAndInvalidAmountsNeverRequestFees() async throws {
        let rig = try TransferTestRig(); defer { rig.fixture.context.cleanup() }
        rig.gate.enabled = false
        await rig.store.review(amount: "10", wallet: rig.fixture.wallet)
        XCTAssertEqual(rig.fees.reads, 0)
        rig.gate.enabled = true
        for amount in ["0", "-1", "1e2", "1.1234567", "", "18446744073709551616"] {
            await rig.store.review(amount: amount, wallet: rig.fixture.wallet)
            XCTAssertNotNil(rig.store.errorMessage)
        }
        XCTAssertEqual(rig.fees.reads, 0)
        XCTAssertEqual(rig.fixture.keychain.reads, 0)
    }

    func testEachExplicitStepUsesSameAmountAndOnlySubmissionBroadcasts() async throws {
        let rig = try TransferTestRig(); defer { rig.fixture.context.cleanup() }
        await rig.store.review(amount: "10", wallet: rig.fixture.wallet)
        XCTAssertEqual(rig.store.display.phase, .authorization)
        XCTAssertEqual(rig.store.display.details?.amount, 10_000_000)
        XCTAssertEqual(rig.fixture.keychain.reads, 0)
        await rig.store.review(amount: "15", wallet: rig.fixture.wallet)
        XCTAssertEqual(rig.fees.reads, 1)
        XCTAssertEqual(rig.store.display.details?.amount, 10_000_000)
        await rig.store.authorize()
        XCTAssertEqual(rig.store.display.phase, .networkFee, rig.store.errorMessage ?? "")
        XCTAssertGreaterThan(try XCTUnwrap(rig.store.display.details?.maximumNetworkFee), FundingQuantity(0))
        XCTAssertEqual(rig.fixture.keychain.reads, 1)
        XCTAssertEqual(rig.broadcast.count, 0)
        await rig.store.sign()
        XCTAssertEqual(rig.store.display.phase, .signed, rig.store.errorMessage ?? "")
        XCTAssertEqual(rig.store.display.entry?.transactionHash?.count, 66)
        XCTAssertEqual(rig.fixture.keychain.reads, 2)
        XCTAssertEqual(rig.broadcast.count, 0)
        await rig.store.submit()
        XCTAssertEqual(rig.store.display.phase, .recorded, rig.store.errorMessage ?? "")
        XCTAssertEqual(rig.store.display.entry?.stage, .nodeAcknowledged)
        XCTAssertTrue(rig.store.display.entry?.stage.requiresReconciliation == true)
        XCTAssertEqual(rig.store.display.details?.amount, 10_000_000)
        XCTAssertEqual(rig.store.display.details?.owner, rig.fixture.wallet.address)
        XCTAssertEqual(rig.store.display.details?.maximumNetworkFee, rig.store.display.entry?.maximumNetworkFee)
        XCTAssertNil(rig.store.display.expiresAt)
        XCTAssertFalse(rig.store.display.canConfirm(at: rig.fixture.context.clock.now))
        await rig.store.submit()
        XCTAssertEqual(rig.broadcast.count, 1)
        XCTAssertEqual(rig.fixture.keychain.reads, 2)
    }

    func testClosedGateAfterFeeResponseCannotPersistConsent() async throws {
        let rig = try TransferTestRig(); defer { rig.fixture.context.cleanup() }
        rig.fees.beforeReturn = { rig.gate.enabled = false }
        await rig.store.review(amount: "10", wallet: rig.fixture.wallet)
        let records = try await rig.fixture.context.journal().consents(wallet: rig.fixture.wallet)
        XCTAssertTrue(records.isEmpty)
        XCTAssertEqual(rig.service.reads, 0)
    }

    func testGateClosedInsideRegistrationStopsAuthorization() async throws {
        let rig = try TransferTestRig(); defer { rig.fixture.context.cleanup() }
        await rig.store.review(amount: "10", wallet: rig.fixture.wallet)
        rig.service.beforeReturn = { rig.gate.enabled = false }
        await rig.store.authorize()
        XCTAssertEqual(rig.fixture.keychain.reads, 0)
        XCTAssertEqual(rig.store.display.phase, .recovery)
    }

    func testClosedGateAfterSignatureCannotBroadcast() async throws {
        let rig = try TransferTestRig(); defer { rig.fixture.context.cleanup() }
        await rig.store.review(amount: "10", wallet: rig.fixture.wallet)
        await rig.store.authorize(); await rig.store.sign()
        rig.gate.enabled = false
        await rig.store.submit()
        XCTAssertEqual(rig.broadcast.count, 0)
        let records = try await rig.fixture.context.journal().records(wallet: rig.fixture.wallet)
        XCTAssertEqual(records.first?.state, .signed)
    }

    func testUncertainSubmissionNeverOffersNewTransferOrRepeatsBroadcast() async throws {
        let rig = try TransferTestRig(); defer { rig.fixture.context.cleanup() }
        rig.broadcast.uncertain = true
        await rig.store.review(amount: "10", wallet: rig.fixture.wallet)
        await rig.store.authorize(); await rig.store.sign(); await rig.store.submit()
        XCTAssertEqual(rig.store.display.entry?.stage, .submissionUnknown)
        XCTAssertEqual(rig.store.display.details?.amount, 10_000_000)
        XCTAssertFalse(rig.store.display.canConfirm(at: rig.fixture.context.clock.now))
        await rig.store.review(amount: "10", wallet: rig.fixture.wallet)
        await rig.store.submit()
        XCTAssertEqual(rig.fees.reads, 1)
        XCTAssertEqual(rig.broadcast.count, 1)
    }

    func testInvalidationDuringFeeReadRejectsLateResult() async throws {
        let rig = try TransferTestRig(); defer { rig.fixture.context.cleanup() }
        rig.fees.beforeReturn = { rig.store.invalidate() }
        await rig.store.review(amount: "10", wallet: rig.fixture.wallet)
        XCTAssertEqual(rig.service.reads, 0)
        XCTAssertEqual(rig.store.display.phase, .amount)
        XCTAssertFalse(rig.store.isBusy)
    }

    func testInsufficientBalanceCanBeCorrectedBeforeAnyIntentExists() async throws {
        let rig = try TransferTestRig(); defer { rig.fixture.context.cleanup() }
        await rig.store.review(amount: "25", wallet: rig.fixture.wallet)
        XCTAssertEqual(rig.store.errorMessage, FundingPreflightError.insufficientUSDC.errorDescription)
        XCTAssertEqual(rig.store.display.phase, .amount)
        let records = try await rig.fixture.context.journal().consents(wallet: rig.fixture.wallet)
        XCTAssertTrue(records.isEmpty)
        await rig.store.review(amount: "10", wallet: rig.fixture.wallet)
        XCTAssertEqual(rig.store.display.phase, .authorization)
    }

    func testCancellingReviewPersistsBeforeStartingAnotherAmount() async throws {
        let rig = try TransferTestRig(); defer { rig.fixture.context.cleanup() }
        await rig.store.review(amount: "10", wallet: rig.fixture.wallet)
        await rig.store.cancelReview()
        XCTAssertEqual(rig.store.display.phase, .amount)
        let history = try await rig.fixture.context.journal().consents(wallet: rig.fixture.wallet)
        XCTAssertEqual(history.first?.state, .cancelled)
        await rig.store.review(amount: "12", wallet: rig.fixture.wallet)
        XCTAssertEqual(rig.store.display.details?.amount, 12_000_000)
        XCTAssertEqual(rig.fixture.keychain.reads, 0)
    }

    func testProjectionCannotConfirmAfterExpiryOrBeforeItsObservation() async throws {
        let rig = try TransferTestRig(); defer { rig.fixture.context.cleanup() }
        await rig.store.review(amount: "10", wallet: rig.fixture.wallet)
        let display = rig.store.display
        XCTAssertTrue(display.canConfirm(at: rig.fixture.context.clock.now))
        XCTAssertFalse(display.canConfirm(at: rig.fixture.context.clock.now.addingTimeInterval(-1)))
        XCTAssertFalse(display.canConfirm(at: try XCTUnwrap(display.expiresAt)))
        await rig.store.authorize()
        let gas = rig.store.display
        XCTAssertEqual(gas.phase, .networkFee)
        rig.fixture.context.clock.advance(31)
        XCTAssertFalse(gas.canConfirm(at: rig.fixture.context.clock.now))
        await rig.store.sign()
        XCTAssertEqual(rig.fixture.keychain.reads, 1)
        XCTAssertEqual(rig.store.display.phase, .recovery)
    }

    func testDepartureAfterSigningKeepsJournalAndNoNewPayment() async throws {
        let rig = try TransferTestRig(); defer { rig.fixture.context.cleanup() }
        await rig.store.review(amount: "10", wallet: rig.fixture.wallet)
        await rig.store.authorize(); await rig.store.sign()
        rig.store.invalidate()
        await rig.store.submit()
        XCTAssertEqual(rig.store.display.phase, .recovery)
        XCTAssertEqual(rig.broadcast.count, 0)
        let records = try await rig.fixture.context.journal().records(wallet: rig.fixture.wallet)
        XCTAssertEqual(records.first?.state, .signed)
    }
}

@MainActor
final class TransferTestRig {
    let fixture: FundingSignerFixture
    let gate = TransferTestGate()
    let service: TransferTestService
    let fees: TransferTestFees
    let source: TransferTestSource
    let broadcast = TransferTestBroadcaster()
    let store: CCTPTransferStore

    init(failures: TransferTestFailures? = nil) throws {
        let fixture = try FundingSignerFixture()
        self.fixture = fixture
        service = TransferTestService(wallet: fixture.wallet)
        fees = TransferTestFees(schedule: fixture.plan.quote.schedule)
        source = TransferTestSource(fixture: fixture, failures: failures)
        let gate = gate
        let preparation = CCTPDepositPreparation(service: service, signer: fixture.signer(),
            journal: try fixture.context.journal(), preflight: source, submissionCheck: source,
            broadcaster: broadcast, clock: { fixture.context.clock.now }, isEnabled: { gate.enabled })
        store = CCTPTransferStore(preparation: preparation, fees: fees, clock: { fixture.context.clock.now },
                                  isEnabled: { gate.enabled })
    }
}

@MainActor final class TransferTestGate { var enabled = true }

@MainActor
final class TransferTestService: AccountWalletServicing {
    let wallet: DeviceWalletSummary
    var reads = 0
    var beforeReturn: (() -> Void)?
    var walletAccountID: UUID? { wallet.accountID }
    init(wallet: DeviceWalletSummary) { self.wallet = wallet }
    func walletRegistration() async throws -> TradingWalletRegistration {
        reads += 1; beforeReturn?()
        return .init(accountId: wallet.accountID, address: wallet.address)
    }
    func fundingSigningLease(wallet: DeviceWalletSummary) throws -> FundingSigningLease { .init(wallet: wallet) }
    func walletChallenge(address: String) async throws -> TradingWalletChallenge { throw DeviceWalletError.invalidProof }
    func bindWallet(challenge: TradingWalletChallenge, signature: String) async throws -> TradingWalletRegistration {
        throw DeviceWalletError.invalidProof
    }
}

@MainActor
final class TransferTestFees: CCTPFeeProviding {
    let value: CCTPFeeSchedule
    var reads = 0
    var beforeReturn: (() -> Void)?
    init(schedule: CCTPFeeSchedule) { value = schedule }
    func schedule() async throws -> CCTPFeeSchedule { reads += 1; beforeReturn?(); return value }
}

struct TransferTestSource: CCTPSourcePreparing, CCTPSourceSubmissionChecking {
    let fixture: FundingSignerFixture
    let failures: TransferTestFailures?
    init(fixture: FundingSignerFixture, failures: TransferTestFailures? = nil) {
        self.fixture = fixture; self.failures = failures
    }
    func snapshot(wallet: DeviceWalletSummary) async throws -> ArbitrumWalletSnapshot {
        let rpc = try PreflightStubRPC(blockTime: fixture.context.clock.now, owner: wallet.address)
        return try await ArbitrumSourcePreflight(rpc: rpc, clock: { fixture.context.clock.now }).snapshot(wallet: wallet)
    }
    func prepare(plan: CCTPDepositPlan, wallet: DeviceWalletSummary, authorization: String) async throws -> CCTPSourcePreflight {
        try await failures?.check()
        let rpc = try PreflightStubRPC(blockTime: fixture.context.clock.now, authorizationNonce: plan.authorizationNonce, owner: wallet.address)
        return try await ArbitrumSourcePreflight(rpc: rpc, clock: { fixture.context.clock.now })
            .prepare(plan: plan, wallet: wallet, authorization: authorization)
    }
    func check(signed: CCTPSignedSourceTransaction, wallet: DeviceWalletSummary) async throws -> FundingSubmissionCheck {
        let gas = await failures?.nextSubmissionGas() ?? 200_000
        let rpc = try PreflightStubRPC(overrides: ["gas": .string(FundingQuantity(gas).rpc)], blockTime: fixture.context.clock.now,
            authorizationNonce: signed.transaction.preflight.plan.authorizationNonce, owner: wallet.address)
        return try await ArbitrumSourceSubmissionCheck(rpc: rpc, clock: { fixture.context.clock.now })
            .check(signed: signed, wallet: wallet)
    }
}

actor TransferTestFailures {
    private var remaining: Int
    private var submissionGas: [UInt64]
    init(_ count: Int, submissionGas: [UInt64] = []) { remaining = count; self.submissionGas = submissionGas }
    func nextSubmissionGas() -> UInt64 { submissionGas.isEmpty ? 200_000 : submissionGas.removeFirst() }
    func check() throws {
        guard remaining > 0 else { return }
        remaining -= 1
        throw FundingPreflightError.simulationFailed
    }
}

@MainActor
final class TransferTestBroadcaster: ArbitrumFundingBroadcasting {
    var count = 0
    var uncertain = false
    func submit(_ permit: FundingSubmissionPermit, lease: FundingSigningLease) async throws -> FundingSubmissionOutcome {
        try permit.start(lease: lease) { _ in count += 1 }
        return uncertain ? .uncertain : .nodeAcknowledged(permit.hash)
    }
}
