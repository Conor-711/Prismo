import XCTest
import Security
@testable import BSmart

@MainActor
final class CCTPDepositPreparationTests: XCTestCase {
    func testTwoExplicitConfirmationsProduceRecordedSignatureNotSubmittedFunds() async throws {
        let fixture = try FundingSignerFixture(); defer { fixture.context.cleanup() }
        let service = FundingRegistrationStub(wallet: fixture.wallet)
        let model = try makeModel(fixture, service: service)
        await model.review(plan: fixture.plan, wallet: fixture.wallet)
        guard case .reviewAuthorization = model.state else { return XCTFail("Missing authorization review") }
        XCTAssertEqual(fixture.keychain.reads, 0)
        await model.authorize()
        guard case .reviewNetworkFee(let transaction) = model.state else { return XCTFail("Missing network fee review: \(model.errorMessage ?? "")") }
        XCTAssertGreaterThan(transaction.preflight.maximumNetworkFee, FundingQuantity(0))
        XCTAssertEqual(fixture.keychain.reads, 1)
        await model.signConfirmedTransaction()
        guard case .signatureRecorded(let record) = model.state else { return XCTFail("Signature not recorded") }
        XCTAssertEqual(record.state, .signed)
        XCTAssertEqual(record.intent.accountID, fixture.wallet.accountID)
        XCTAssertTrue(record.reservesNonce)
        XCTAssertEqual(fixture.keychain.reads, 2)
        XCTAssertEqual(service.reads, 3)
        await model.signConfirmedTransaction()
        XCTAssertEqual(fixture.keychain.reads, 2)
    }

    func testAccountRegistrationMustMatchBeforeAnyProtectedRead() async throws {
        let fixture = try FundingSignerFixture(); defer { fixture.context.cleanup() }
        let service = FundingRegistrationStub(wallet: fixture.wallet)
        service.address = PreflightTestFixture.wallet.address
        let model = try makeModel(fixture, service: service)
        await model.review(plan: fixture.plan, wallet: fixture.wallet)
        XCTAssertEqual(fixture.keychain.reads, 0)
        let records = try await fixture.context.journal().consents(wallet: fixture.wallet)
        XCTAssertTrue(records.isEmpty)
        guard case .idle = model.state else { return XCTFail("Unverified registration advanced") }
    }

    func testSessionChangeBeforeAuthorizationCannotReachSigner() async throws {
        let fixture = try FundingSignerFixture(); defer { fixture.context.cleanup() }
        let service = FundingRegistrationStub(wallet: fixture.wallet)
        let model = try makeModel(fixture, service: service)
        await model.review(plan: fixture.plan, wallet: fixture.wallet)
        service.walletAccountID = UUID()
        await model.authorize()
        XCTAssertEqual(fixture.keychain.reads, 0)
        let records = try await fixture.context.journal().consents(wallet: fixture.wallet)
        XCTAssertEqual(records.first?.state, .review)
    }

    func testInvalidationAfterAuthorizationStillArchivesEvidenceAndStopsPreflight() async throws {
        let fixture = try FundingSignerFixture(); defer { fixture.context.cleanup() }
        let signer = FundingCallbackSigner(base: fixture.signer())
        let model = try makeModel(fixture, signer: signer)
        signer.afterAuthorization = { model.invalidate() }
        await model.review(plan: fixture.plan, wallet: fixture.wallet)
        await model.authorize()
        guard case .recoveryRequired = model.state else { return XCTFail("Invalidated UI advanced") }
        let records = try await fixture.context.journal().consents(wallet: fixture.wallet)
        let sources = try await fixture.context.journal().records(wallet: fixture.wallet)
        XCTAssertEqual(records.first?.state, .authorized)
        XCTAssertNotNil(records.first?.signature)
        XCTAssertTrue(sources.isEmpty)
    }

    func testInvalidationAfterSourceSigningStillArchivesExactTransaction() async throws {
        let fixture = try FundingSignerFixture(); defer { fixture.context.cleanup() }
        let signer = FundingCallbackSigner(base: fixture.signer())
        let model = try makeModel(fixture, signer: signer)
        signer.afterSource = { model.invalidate() }
        await model.review(plan: fixture.plan, wallet: fixture.wallet)
        await model.authorize()
        await model.signConfirmedTransaction()
        guard case .recoveryRequired = model.state else { return XCTFail("Invalidated UI advanced") }
        let sources = try await fixture.context.journal().records(wallet: fixture.wallet)
        XCTAssertEqual(sources.first?.state, .signed)
        XCTAssertNotNil(sources.first?.signed?.raw)
        XCTAssertTrue(sources.first?.reservesNonce == true)
    }

    func testExpiredNetworkFeeCannotTriggerSecondProtectedRead() async throws {
        let fixture = try FundingSignerFixture(); defer { fixture.context.cleanup() }
        let model = try makeModel(fixture)
        await model.review(plan: fixture.plan, wallet: fixture.wallet)
        await model.authorize()
        guard case .reviewNetworkFee = model.state else { return XCTFail("Missing network fee review") }
        fixture.context.clock.advance(31)
        await model.signConfirmedTransaction()
        XCTAssertEqual(fixture.keychain.reads, 1)
        let sources = try await fixture.context.journal().records(wallet: fixture.wallet)
        XCTAssertEqual(sources.first?.state, .prepared)
        XCTAssertNil(sources.first?.signed)
    }

    func testCancellingEitherUnsignedReviewPersistsCancellationWithoutSigning() async throws {
        for afterAuthorization in [false, true] {
            let fixture = try FundingSignerFixture(); defer { fixture.context.cleanup() }
            let model = try makeModel(fixture)
            await model.review(plan: fixture.plan, wallet: fixture.wallet)
            if afterAuthorization { await model.authorize() }
            await model.cancelUnsignedReview()
            guard case .idle = model.state else { return XCTFail("Unsigned review was not cancelled") }
            XCTAssertEqual(fixture.keychain.reads, afterAuthorization ? 1 : 0)
            if afterAuthorization {
                let records = try await fixture.context.journal().records(wallet: fixture.wallet)
                XCTAssertEqual(records.first?.state, .cancelled)
            } else {
                let records = try await fixture.context.journal().consents(wallet: fixture.wallet)
                XCTAssertEqual(records.first?.state, .cancelled)
            }
        }
    }

    func testFailedKeyAccessRemainsAuthorizingWithoutNoFundsClaim() async throws {
        let fixture = try FundingSignerFixture(); defer { fixture.context.cleanup() }
        let model = try makeModel(fixture)
        await model.review(plan: fixture.plan, wallet: fixture.wallet)
        fixture.keychain.status = errSecNotAvailable
        await model.authorize()
        let history = try await fixture.context.journal().consents(wallet: fixture.wallet)
        XCTAssertEqual(history.first?.state, .authorizing)
        XCTAssertNil(history.first?.signature)
        XCTAssertEqual(model.errorMessage, FundingJournalError.unavailable.errorDescription)
        let reads = fixture.keychain.reads
        await model.authorize()
        XCTAssertEqual(fixture.keychain.reads, reads)
    }

    func testInsufficientSourceFundsStopBeforeConsentOrKeyAccess() async throws {
        for field in ["usdc", "eth"] {
            let fixture = try FundingSignerFixture(); defer { fixture.context.cleanup() }
            let zero: FundingRPCValue = .string(field == "eth" ? "0x0" : FundingQuantity(0).abi)
            let model = try makeModel(fixture, rpcOverrides: [field: zero])
            await model.review(plan: fixture.plan, wallet: fixture.wallet)
            await model.authorize()
            XCTAssertEqual(fixture.keychain.reads, 0)
            let records = try await fixture.context.journal().consents(wallet: fixture.wallet)
            XCTAssertTrue(records.isEmpty)
        }
    }

    func testExplicitSubmissionArchivesNodeAcknowledgementWithoutClaimingCreditOrResigning() async throws {
        let fixture = try FundingSignerFixture(); defer { fixture.context.cleanup() }
        let service = FundingRegistrationStub(wallet: fixture.wallet)
        let broadcaster = FundingBroadcastStub()
        let model = try makeModel(fixture, service: service, broadcaster: broadcaster)
        await prepareSigned(model, fixture: fixture)
        XCTAssertEqual(broadcaster.started, 0)
        await model.submitConfirmedTransaction()
        guard case .submissionRecorded(let entry) = model.state else { return XCTFail(model.errorMessage ?? "Missing submission result") }
        XCTAssertEqual(entry.stage, .nodeAcknowledged)
        XCTAssertTrue(entry.stage.requiresReconciliation)
        XCTAssertEqual(service.reads, 4)
        XCTAssertEqual(fixture.keychain.reads, 2)
        await model.submitConfirmedTransaction()
        XCTAssertEqual(broadcaster.started, 1)
        let records = try await fixture.context.journal().records(wallet: fixture.wallet)
        XCTAssertEqual(records.first?.state, .submitted)
        XCTAssertTrue(records.first?.reservesNonce == true)
    }

    func testTimeoutWrongHashOrThrownTransportErrorPreserveUncertainRecord() async throws {
        for mode in [FundingBroadcastStub.Mode.uncertain, .wrongHash, .throwsError] {
            let fixture = try FundingSignerFixture(); defer { fixture.context.cleanup() }
            let broadcaster = FundingBroadcastStub(mode: mode)
            let model = try makeModel(fixture, broadcaster: broadcaster)
            await prepareSigned(model, fixture: fixture)
            await model.submitConfirmedTransaction()
            guard case .submissionRecorded(let entry) = model.state else { return XCTFail("Missing uncertain state") }
            XCTAssertEqual(entry.stage, .submissionUnknown)
            await model.submitConfirmedTransaction()
            XCTAssertEqual(broadcaster.started, 1)
            let records = try await fixture.context.journal().records(wallet: fixture.wallet)
            XCTAssertEqual(records.first?.state, .uncertain)
            XCTAssertNotNil(records.first?.signed?.raw)
        }
    }

    func testSourceChangeAfterSignaturePreventsBroadcast() async throws {
        let fixture = try FundingSignerFixture(); defer { fixture.context.cleanup() }
        let changedRPC = try PreflightStubRPC(overrides: ["pendingNonce": .string("0x1")], owner: fixture.wallet.address)
        let checker = ArbitrumSourceSubmissionCheck(rpc: changedRPC, clock: { fixture.context.clock.now })
        let broadcaster = FundingBroadcastStub()
        let model = try makeModel(fixture, checker: checker, broadcaster: broadcaster)
        await prepareSigned(model, fixture: fixture)
        await model.submitConfirmedTransaction()
        XCTAssertEqual(broadcaster.started, 0)
        let records = try await fixture.context.journal().records(wallet: fixture.wallet)
        XCTAssertEqual(records.first?.state, .notSubmitted)
        XCTAssertFalse(records.first?.needsReconciliation == true)
        XCTAssertNotNil(records.first?.signed?.raw)
        guard case .idle = model.state else { return XCTFail("Pre-submit failure blocked another quote") }
    }

    func testInvalidationDuringFreshCheckPreventsSubmitPermission() async throws {
        let fixture = try FundingSignerFixture(); defer { fixture.context.cleanup() }
        let rpc = try PreflightStubRPC(owner: fixture.wallet.address)
        let checker = FundingCallbackCheck(base: ArbitrumSourceSubmissionCheck(rpc: rpc, clock: { fixture.context.clock.now }))
        let broadcaster = FundingBroadcastStub()
        let model = try makeModel(fixture, checker: checker, broadcaster: broadcaster)
        checker.afterCheck = { model.invalidate() }
        await prepareSigned(model, fixture: fixture)
        await model.submitConfirmedTransaction()
        XCTAssertEqual(broadcaster.started, 0)
        let records = try await fixture.context.journal().records(wallet: fixture.wallet)
        XCTAssertEqual(records.first?.state, .signed)
    }

    func testDepartureOrAccountChangeAfterStartStillArchivesObservedResult() async throws {
        for switchAccount in [false, true] {
            let fixture = try FundingSignerFixture(); defer { fixture.context.cleanup() }
            let service = FundingRegistrationStub(wallet: fixture.wallet)
            let broadcaster = FundingBroadcastStub()
            let model = try makeModel(fixture, service: service, broadcaster: broadcaster)
            broadcaster.beforeResponse = {
                if switchAccount { service.walletAccountID = UUID() }
                else { model.invalidate() }
            }
            await prepareSigned(model, fixture: fixture)
            await model.submitConfirmedTransaction()
            guard case .recoveryRequired = model.state else { return XCTFail("Obsolete UI advanced") }
            let records = try await fixture.context.journal().records(wallet: fixture.wallet)
            XCTAssertEqual(records.first?.state, .submitted)
            XCTAssertEqual(broadcaster.started, 1)
            await model.submitConfirmedTransaction()
            XCTAssertEqual(broadcaster.started, 1)
        }
    }

    func testCancelledTaskStillRecordsAcknowledgementAfterStart() async throws {
        let fixture = try FundingSignerFixture(); defer { fixture.context.cleanup() }
        let broadcaster = FundingBroadcastStub()
        let model = try makeModel(fixture, broadcaster: broadcaster)
        broadcaster.beforeResponse = { withUnsafeCurrentTask { $0?.cancel() } }
        await prepareSigned(model, fixture: fixture)
        await Task { await model.submitConfirmedTransaction() }.value
        let records = try await fixture.context.journal().records(wallet: fixture.wallet)
        XCTAssertEqual(records.first?.state, .submitted)
        XCTAssertEqual(broadcaster.started, 1)
        guard case .recoveryRequired = model.state else { return XCTFail("Cancelled UI advanced") }
    }

    private func prepareSigned(_ model: CCTPDepositPreparation, fixture: FundingSignerFixture) async {
        await model.review(plan: fixture.plan, wallet: fixture.wallet)
        await model.authorize()
        await model.signConfirmedTransaction()
        guard case .signatureRecorded = model.state else { return XCTFail(model.errorMessage ?? "Expected recorded signature") }
    }

    private func makeModel(_ fixture: FundingSignerFixture, service: FundingRegistrationStub? = nil,
                           signer: FundingDeviceSigning? = nil, rpcOverrides: [String: FundingRPCValue] = [:],
                           checker: CCTPSourceSubmissionChecking? = nil, broadcaster: FundingBroadcastStub? = nil) throws -> CCTPDepositPreparation {
        let rpc = try PreflightStubRPC(overrides: rpcOverrides, blockTime: fixture.context.clock.now, owner: fixture.wallet.address)
        return .init(service: service ?? FundingRegistrationStub(wallet: fixture.wallet), signer: signer ?? fixture.signer(),
                      journal: try fixture.context.journal(), preflight: ArbitrumSourcePreflight(rpc: rpc, clock: { fixture.context.clock.now }),
                      submissionCheck: checker ?? ArbitrumSourceSubmissionCheck(rpc: rpc, clock: { fixture.context.clock.now }),
                      broadcaster: broadcaster ?? FundingBroadcastStub(),
                      clock: { fixture.context.clock.now }, isEnabled: { true })
    }
}

@MainActor
private final class FundingBroadcastStub: ArbitrumFundingBroadcasting {
    enum Mode { case success, uncertain, wrongHash, throwsError }
    let mode: Mode
    private(set) var started = 0
    var beforeResponse: (() -> Void)?
    init(mode: Mode = .success) { self.mode = mode }
    func submit(_ permit: FundingSubmissionPermit, lease: FundingSigningLease) async throws -> FundingSubmissionOutcome {
        try permit.start(lease: lease) { _ in started += 1 }
        beforeResponse?()
        switch mode {
        case .success: return .nodeAcknowledged(permit.hash)
        case .uncertain: return .uncertain
        case .wrongHash: return .nodeAcknowledged("0x" + String(repeating: "ab", count: 32))
        case .throwsError: throw URLError(.timedOut)
        }
    }
}

@MainActor
private final class FundingCallbackCheck: CCTPSourceSubmissionChecking {
    let base: CCTPSourceSubmissionChecking
    var afterCheck: (() -> Void)?
    init(base: CCTPSourceSubmissionChecking) { self.base = base }
    func check(signed: CCTPSignedSourceTransaction, wallet: DeviceWalletSummary) async throws -> FundingSubmissionCheck {
        let result = try await base.check(signed: signed, wallet: wallet)
        afterCheck?()
        return result
    }
}

@MainActor
private final class FundingRegistrationStub: AccountWalletServicing {
    var walletAccountID: UUID?
    var address: String?
    private(set) var reads = 0
    init(wallet: DeviceWalletSummary) { walletAccountID = wallet.accountID; address = wallet.address }
    func walletRegistration() async throws -> TradingWalletRegistration {
        reads += 1
        return .init(accountId: try XCTUnwrap(walletAccountID), address: address)
    }
    func fundingSigningLease(wallet: DeviceWalletSummary) throws -> FundingSigningLease {
        guard wallet.accountID == walletAccountID else { throw FundingJournalError.conflict }
        return .init(wallet: wallet)
    }
    func walletChallenge(address: String) async throws -> TradingWalletChallenge { throw FundingJournalError.unavailable }
    func bindWallet(challenge: TradingWalletChallenge, signature: String) async throws -> TradingWalletRegistration {
        throw FundingJournalError.unavailable
    }
}

@MainActor
private final class FundingCallbackSigner: FundingDeviceSigning {
    let base: FundingDeviceSigning
    var afterAuthorization: (() -> Void)?
    var afterSource: (() -> Void)?
    init(base: FundingDeviceSigning) { self.base = base }
    func authorizeDeposit(_ permit: FundingAuthorizationPermit, lease: FundingSigningLease) async throws -> String {
        let result = try await base.authorizeDeposit(permit, lease: lease)
        afterAuthorization?()
        return result
    }
    func signDeposit(_ permit: FundingSigningPermit, transaction: CCTPSourceTransaction, lease: FundingSigningLease) async throws -> Data {
        let result = try await base.signDeposit(permit, transaction: transaction, lease: lease)
        afterSource?()
        return result
    }
}
