import XCTest
import WalletCore
@testable import BSmart

final class HyperliquidWithdrawalJournalTests: XCTestCase {
    typealias F = HyperliquidTradingFixture

    func testArchiveRoundTripAndWrongAccount() throws {
        let context = WithdrawalJournalContext(); defer { context.base.cleanup() }
        let intent = try context.intent(), archive = HyperliquidArchivedWithdrawal(intent)
        let restored = try JSONDecoder().decode(HyperliquidArchivedWithdrawal.self, from: JSONEncoder().encode(archive))
        XCTAssertEqual(try restored.restored(wallet: F.wallet), intent)
        XCTAssertThrowsError(try restored.restored(wallet: .init(accountID: UUID(), address: F.wallet.address, recoveryVerified: true)))
    }

    func testUnsignedReviewMayCancelButNeverReusesNonce() async throws {
        let context = WithdrawalJournalContext(); defer { context.base.cleanup() }
        let (journal, intent, id) = try await context.review()
        let cancelled = try await journal.cancelWithdrawalReview(id: id, wallet: F.wallet)
        XCTAssertEqual(cancelled.state, .cancelled)
        let second = try await journal.cancelWithdrawalReview(id: id, wallet: F.wallet)
        XCTAssertEqual(second, cancelled)
        let next = try await context.base.journal().nextOrderNonce(wallet: F.wallet)
        XCTAssertEqual(next, intent.nonce + 1)
        await expectJournalFailure { try await journal.reserveWithdrawal(id: UUID(), intent: intent, wallet: F.wallet) }
        _ = try await journal.reserveWithdrawal(id: UUID(), intent: context.intent(nonce: next), wallet: F.wallet)
    }

    func testSigningCannotBeCancelledOrReleasedByTimeOrRestart() async throws {
        let context = WithdrawalJournalContext(); defer { context.base.cleanup() }
        let (journal, intent, id) = try await context.review()
        _ = try await journal.recordWithdrawalSigningStarted(id: id, intent: intent, wallet: F.wallet)
        context.base.clock.advance(wall: 86_400, steady: .seconds(86_400))
        let resumed = try context.base.journal()
        await expectJournalFailure { try await resumed.cancelWithdrawalReview(id: id, wallet: F.wallet) }
        await expectJournalFailure { try await resumed.reserveWithdrawal(id: UUID(), intent: context.intent(), wallet: F.wallet) }
        let history = try await resumed.withdrawalRecords(wallet: F.wallet)
        XCTAssertEqual(history.first?.state, .signing)
        XCTAssertEqual(history.first?.blocksNewAction(at: context.base.clock.now), true)
    }

    func testExpiredUnsignedReviewCannotSignButAllowsNewNonce() async throws {
        let context = WithdrawalJournalContext(); defer { context.base.cleanup() }
        let (journal, intent, id) = try await context.review()
        context.base.clock.advance(wall: 60, steady: .seconds(60))
        await expectJournalFailure { try await journal.recordWithdrawalSigningStarted(id: id, intent: intent, wallet: F.wallet) }
        _ = try await journal.reserveWithdrawal(id: UUID(), intent: context.intent(), wallet: F.wallet)
    }

    func testSignatureBindsRecipientAndPersistsAfterTaskCancellation() async throws {
        let context = WithdrawalJournalContext(); defer { context.base.cleanup() }
        let (journal, intent, id) = try await context.review()
        _ = try await journal.recordWithdrawalSigningStarted(id: id, intent: intent, wallet: F.wallet)
        let wrong = try context.intent(recipient: "0x3333333333333333333333333333333333333333")
        await expectJournalFailure { try await journal.recordWithdrawalSignature(id: id, signature: context.signature(wrong), wallet: F.wallet) }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await journal.recordWithdrawalSignature(id: id, signature: context.signature(intent), wallet: F.wallet)
        }
        let signed = try await task.value
        XCTAssertEqual(signed.state, .signed)
        let history = try await context.base.journal().withdrawalRecords(wallet: F.wallet)
        XCTAssertEqual(history.first, signed)
    }

    func testSignedBytesAreEncryptedOnDisk() async throws {
        let context = WithdrawalJournalContext(); defer { context.base.cleanup() }
        let (_, _, _, signed) = try await context.signed()
        let database = try Data(contentsOf: context.base.directory.appendingPathComponent("transactions.sqlite"))
        let signature = try XCTUnwrap(signed.signature)
        XCTAssertNil(database.range(of: Data(signature.utf8)))
        XCTAssertNil(database.range(of: Data(signed.intent.recipient.utf8)))
        let restored = try await context.base.journal().withdrawalRecords(wallet: F.wallet)
        XCTAssertEqual(restored.first, signed)
    }

    func testUnknownReplyCannotBeReplayedOrConvertedToRejected() async throws {
        let context = WithdrawalJournalContext(); defer { context.base.cleanup() }
        let (journal, intent, id) = try await context.submitting()
        let unknown = try await journal.recordWithdrawalResponse(id: id, response: Data(#"{"status":"ok"}"#.utf8), wallet: F.wallet)
        XCTAssertEqual(unknown.state, .uncertain)
        XCTAssertNil(unknown.response)
        await expectJournalFailure { try await journal.recordWithdrawalSubmissionStarted(id: id, intent: intent, wallet: F.wallet) }
        await expectJournalFailure { try await journal.recordWithdrawalResponse(id: id, response: WithdrawalJournalContext.rejected, wallet: F.wallet) }
        context.base.clock.advance(wall: 3600, steady: .seconds(3600))
        await expectJournalFailure { try await journal.reserveWithdrawal(id: UUID(), intent: context.intent(), wallet: F.wallet) }
    }

    func testAcceptedDoesNotMeanArrivedButPermitsANewExplicitWithdrawal() async throws {
        let context = WithdrawalJournalContext(); defer { context.base.cleanup() }
        let (journal, _, id) = try await context.submitting()
        let record = try await journal.recordWithdrawalResponse(id: id, response: WithdrawalJournalContext.accepted, wallet: F.wallet)
        XCTAssertEqual(record.state, .accepted)
        XCTAssertEqual(record.acknowledgement, .accepted)
        XCTAssertFalse(record.blocksNewAction(at: context.base.clock.now))
        let history = try await context.base.journal().withdrawalRecords(wallet: F.wallet)
        XCTAssertEqual(history.first, record)
        let nonce = try await journal.nextHyperliquidNonce(wallet: F.wallet)
        XCTAssertGreaterThan(nonce, record.intent.nonce)
        _ = try await journal.reserveWithdrawal(id: UUID(), intent: context.intent(nonce: nonce), wallet: F.wallet)
        await expectJournalFailure { try await journal.recordWithdrawalSubmissionStarted(id: id, intent: context.intent(), wallet: F.wallet) }
    }

    func testKnownFirstRejectionReleasesReservationButNotNonce() async throws {
        let context = WithdrawalJournalContext(); defer { context.base.cleanup() }
        let (journal, intent, id) = try await context.submitting()
        let result = try await journal.recordWithdrawalResponse(id: id, response: WithdrawalJournalContext.rejected, wallet: F.wallet)
        XCTAssertEqual(result.state, .rejected)
        XCTAssertFalse(result.blocksNewAction(at: context.base.clock.now))
        let next = try await journal.nextOrderNonce(wallet: F.wallet)
        XCTAssertEqual(next, intent.nonce + 1)
        _ = try await journal.reserveWithdrawal(id: UUID(), intent: context.intent(nonce: next), wallet: F.wallet)
    }

    func testCommitFailureRetainsSubmissionAndNeverReissues() async throws {
        let context = WithdrawalJournalContext(); defer { context.base.cleanup() }
        let (_, intent, id, _) = try await context.signed()
        let failing = try context.base.journal { if $0 == .afterCommit { throw FundingJournalError.unavailable } }
        await expectJournalFailure { try await failing.recordWithdrawalSubmissionStarted(id: id, intent: intent, wallet: F.wallet) }
        let resumed = try context.base.journal()
        let history = try await resumed.withdrawalRecords(wallet: F.wallet)
        XCTAssertEqual(history.first?.state, .submitting)
        await expectJournalFailure { try await resumed.recordWithdrawalSubmissionStarted(id: id, intent: intent, wallet: F.wallet) }
    }

    func testResponseAfterCancellationStillPersists() async throws {
        let context = WithdrawalJournalContext(); defer { context.base.cleanup() }
        let (journal, _, id) = try await context.submitting()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await journal.recordWithdrawalResponse(id: id, response: WithdrawalJournalContext.accepted, wallet: F.wallet)
        }
        let result = try await task.value
        XCTAssertEqual(result.state, .accepted)
    }

    func testSignatureAfterClockRollbackIsStillDurable() async throws {
        let context = WithdrawalJournalContext(); defer { context.base.cleanup() }
        let (journal, intent, id) = try await context.review()
        let started = try await journal.recordWithdrawalSigningStarted(id: id, intent: intent, wallet: F.wallet)
        context.base.clock.advance(wall: -120, steady: .seconds(1))
        let signed = try await journal.recordWithdrawalSignature(id: id, signature: context.signature(intent), wallet: F.wallet)
        XCTAssertEqual(signed.state, .signed)
        XCTAssertEqual(signed.updatedAt, started.updatedAt)
        let history = try await context.base.journal().withdrawalRecords(wallet: F.wallet)
        XCTAssertEqual(history.first, signed)
    }

    func testResponseAfterClockRollbackIsStillDurable() async throws {
        let context = WithdrawalJournalContext(); defer { context.base.cleanup() }
        let (journal, _, id) = try await context.submitting()
        context.base.clock.advance(wall: -120, steady: .seconds(1))
        let result = try await journal.recordWithdrawalResponse(id: id, response: WithdrawalJournalContext.accepted, wallet: F.wallet)
        XCTAssertEqual(result.state, .accepted)
        let history = try await context.base.journal().withdrawalRecords(wallet: F.wallet)
        XCTAssertEqual(history.first, result)
    }

    func testWrongAccountCannotReadOrAdvanceAnotherWithdrawal() async throws {
        let context = WithdrawalJournalContext(); defer { context.base.cleanup() }
        let (journal, intent, id) = try await context.review()
        let other = DeviceWalletSummary(accountID: UUID(), address: F.wallet.address, recoveryVerified: true)
        let records = try await journal.withdrawalRecords(wallet: other)
        XCTAssertTrue(records.isEmpty)
        await expectJournalFailure { try await journal.cancelWithdrawalReview(id: id, wallet: other) }
        await expectJournalFailure { try await journal.recordWithdrawalSigningStarted(id: id, intent: intent, wallet: other) }
    }

    func testNonceAndMutableTermsAreCheckedOnReplay() async throws {
        let context = WithdrawalJournalContext(); defer { context.base.cleanup() }
        let (journal, intent, id) = try await context.review()
        let records = try await journal.withdrawalRecords(wallet: F.wallet)
        let first = try XCTUnwrap(records.first)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(first)) as? [String: Any])
        var archived = try XCTUnwrap(object["intent"] as? [String: Any]); archived["amount"] = "010"
        object["intent"] = archived
        let malformed = try JSONDecoder().decode(HyperliquidWithdrawalRecord.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try malformed.validate(after: nil))
        var changed = first; changed.state = .signing; changed.updatedAt = first.reviewExpiresAt
        XCTAssertThrowsError(try changed.validate(after: first))
        let event = FundingJournalEvent.withdrawal(first)
        let decoded = try JSONDecoder().decode(FundingJournalEvent.self, from: JSONEncoder().encode(event))
        var replay = FundingJournalSnapshot(); try replay.apply(decoded)
        XCTAssertThrowsError(try replay.apply(decoded))
        XCTAssertEqual(replay.latestHyperliquidNonce(owner: intent.owner), intent.nonce)
        XCTAssertEqual(replay.withdrawals[id], first)
    }

    func testRejectsMalformedAcknowledgements() throws {
        for json in [#"{"status":"ok"}"#, #"{"status":"ok","response":{"type":"order"}}"#,
                     #"{"status":"ok","response":{"type":"default","error":"failed"}}"#,
                     #"{"status":"ok","response":{"type":"default"},"error":"failed"}"#,
                     #"{"status":"err","response":""}"#, #"{"status":"err","response":42}"#,
                     #"{"status":"err","response":"\u0001bad"}"#] {
            XCTAssertThrowsError(try HyperliquidWithdrawalAcknowledgement.decode(Data(json.utf8)))
        }
        XCTAssertThrowsError(try HyperliquidWithdrawalAcknowledgement.decode(Data(repeating: 32, count: 8193)))
        XCTAssertEqual(try HyperliquidWithdrawalAcknowledgement.decode(WithdrawalJournalContext.accepted), .accepted)
    }
}

struct WithdrawalJournalContext: Sendable {
    typealias F = HyperliquidTradingFixture
    let base = OrderLifecycleContext()
    static let accepted = Data(#"{"status":"ok","response":{"type":"default"}}"#.utf8)
    static let rejected = Data(#"{"status":"err","response":"Insufficient balance"}"#.utf8)

    func intent(nonce: UInt64? = nil, recipient: String = "0x2222222222222222222222222222222222222222",
                wallet: DeviceWalletSummary = F.wallet) throws -> HyperliquidWithdrawalIntent {
        try .init(wallet: wallet, recipient: recipient, amount: "10", source: .spot,
                  nonce: nonce ?? UInt64(base.clock.now.timeIntervalSince1970 * 1000))
    }

    func signature(_ intent: HyperliquidWithdrawalIntent) throws -> String {
        let key = try XCTUnwrap(PrivateKey(data: Data(repeating: 0, count: 31) + Data([1])))
        let raw = EthereumMessageSigner.signTypedMessage(privateKey: key, messageJson: try HyperliquidWithdrawalCodec.typedJSON(intent))
        return raw.hasPrefix("0x") ? raw : "0x" + raw
    }

    func review() async throws -> (FundingTransactionJournal, HyperliquidWithdrawalIntent, UUID) {
        let journal = try base.journal(), intent = try intent(), id = UUID()
        _ = try await journal.reserveWithdrawal(id: id, intent: intent, wallet: F.wallet)
        return (journal, intent, id)
    }

    func signed() async throws -> (FundingTransactionJournal, HyperliquidWithdrawalIntent, UUID, HyperliquidWithdrawalRecord) {
        let (journal, intent, id) = try await review()
        _ = try await journal.recordWithdrawalSigningStarted(id: id, intent: intent, wallet: F.wallet)
        let signed = try await journal.recordWithdrawalSignature(id: id, signature: signature(intent), wallet: F.wallet)
        return (journal, intent, id, signed)
    }

    func submitting() async throws -> (FundingTransactionJournal, HyperliquidWithdrawalIntent, UUID) {
        let (journal, intent, id, _) = try await signed()
        _ = try await journal.recordWithdrawalSubmissionStarted(id: id, intent: intent, wallet: F.wallet)
        return (journal, intent, id)
    }
}
