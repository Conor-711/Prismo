import XCTest
import WalletCore
@testable import BSmart

final class HyperliquidOrderLifecycleTests: XCTestCase {
    typealias F = HyperliquidTradingFixture
    typealias Q = HyperliquidQuoteFixture

    func testArchiveRoundTripRetainsExactSignedPayload() throws {
        let original = try Q.order()
        let archive = try HyperliquidArchivedOrder(original)
        let decoded = try JSONDecoder().decode(HyperliquidArchivedOrder.self, from: JSONEncoder().encode(archive))
        XCTAssertEqual(try decoded.restored(wallet: F.wallet), original)
        XCTAssertThrowsError(try HyperliquidArchivedOrder(Q.order(builder: .init(address: Q.recipient, tenthsOfBasisPoint: 10))))
    }

    func testSigningAndSubmissionPermitsAreOneUseAcrossJournalRestart() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let journal = try context.journal(), quote = try await context.preview(), id = UUID()
        _ = try await journal.reserveOrder(id: id, preview: quote, wallet: F.wallet, continuousNow: context.clock.instant)
        let signer = try await journal.beginOrderSigning(id: id, preview: quote, wallet: F.wallet, continuousNow: context.clock.instant)
        try signer.consume(wallet: F.wallet, now: context.clock.now, continuousNow: context.clock.instant)
        XCTAssertThrowsError(try signer.consume(wallet: F.wallet, now: context.clock.now, continuousNow: context.clock.instant))
        _ = try await journal.recordOrderSignature(id: id, signature: context.signature(quote.order), wallet: F.wallet)
        let resumed = try context.journal()
        let permit = try await resumed.beginOrderSubmission(id: id, preview: quote, wallet: F.wallet,
                                                            continuousClock: { context.clock.instant })
        let scope = context.lease()
        let body = try permit.start(lease: scope) { $0 }
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil((json["action"] as? [String: Any])?["builder"])
        XCTAssertThrowsError(try permit.start(lease: scope) { $0 })
        await expectJournalFailure {
            try await resumed.beginOrderSubmission(id: id, preview: quote, wallet: F.wallet, continuousClock: { context.clock.instant })
        }
        let response = Data(#"{"status":"ok","response":{"type":"order","data":{"statuses":[{"filled":{"totalSz":"1","avgPx":"220","oid":25}}]}}}"#.utf8)
        let result = try await resumed.recordOrderResponse(id: id, response: response, wallet: F.wallet)
        guard case .filled(let fill) = result.acknowledgement else { return XCTFail("Expected real partial acknowledgement") }
        XCTAssertFalse(fill.isComplete)
        XCTAssertEqual(fill.size.wire, "1")
        let history = try await context.journal().orderRecords(wallet: F.wallet)
        XCTAssertEqual(history.first, result)
    }

    func testUnknownResponseBlocksAnotherOrderAndCannotBeResubmitted() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let (journal, quote, id) = try await context.submitting()
        let unknown = try await journal.recordOrderResponse(id: id, response: Data(#"{"status":"ok"}"#.utf8), wallet: F.wallet)
        XCTAssertEqual(unknown.state, .uncertain)
        XCTAssertNil(unknown.acknowledgement)
        await expectJournalFailure {
            try await journal.reserveOrder(id: UUID(), preview: quote, wallet: F.wallet, continuousNow: context.clock.instant)
        }
        await expectJournalFailure {
            try await journal.beginOrderSubmission(id: id, preview: quote, wallet: F.wallet, continuousClock: { context.clock.instant })
        }
    }

    func testCancelledTaskStillPersistsReturnedResponse() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let (journal, _, id) = try await context.submitting()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await journal.recordOrderResponse(id: id, response: Data(#"{"status":"err","response":"Insufficient margin"}"#.utf8), wallet: F.wallet)
        }
        let result = try await task.value
        XCTAssertEqual(result.state, .rejected)
        let history = try await journal.orderRecords(wallet: F.wallet)
        XCTAssertEqual(history.first, result)
    }

    func testSignatureAndAccountMismatchDoNotAdvanceJournal() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let journal = try context.journal(), quote = try await context.preview(), id = UUID()
        _ = try await journal.reserveOrder(id: id, preview: quote, wallet: F.wallet, continuousNow: context.clock.instant)
        _ = try await journal.beginOrderSigning(id: id, preview: quote, wallet: F.wallet, continuousNow: context.clock.instant)
        await expectJournalFailure { try await journal.recordOrderSignature(id: id, signature: "0x00", wallet: F.wallet) }
        let wrong = DeviceWalletSummary(accountID: UUID(), address: F.wallet.address, recoveryVerified: true)
        await expectJournalFailure { try await journal.recordOrderSignature(id: id, signature: context.signature(quote.order), wallet: wrong) }
        let stored = try await journal.orderRecords(wallet: F.wallet)
        XCTAssertEqual(stored.first?.state, .signing)
    }

    func testRevokedLeasePreventsNetworkStart() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let (_, _, _, permit) = try await context.permit()
        let scope = context.lease(); scope.invalidate()
        var started = false
        XCTAssertThrowsError(try permit.start(lease: scope) { _ in started = true })
        XCTAssertFalse(started)
    }

    func testStaleBookPreventsSubmissionPermit() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let (journal, quote, id) = try await context.signed()
        context.clock.advance(wall: 6, steady: .seconds(6))
        await expectJournalFailure {
            try await journal.beginOrderSubmission(id: id, preview: quote, wallet: F.wallet, continuousClock: { context.clock.instant })
        }
        let history = try await journal.orderRecords(wallet: F.wallet)
        XCTAssertEqual(history.first?.state, .signed)
    }

    func testCommitFailureIssuesNoSubmissionPermitAndRestartRetainsUncertainty() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let (_, quote, id) = try await context.signed()
        let failing = try context.journal { if $0 == .afterCommit { throw FundingJournalError.unavailable } }
        await expectJournalFailure {
            try await failing.beginOrderSubmission(id: id, preview: quote, wallet: F.wallet, continuousClock: { context.clock.instant })
        }
        let history = try await context.journal().orderRecords(wallet: F.wallet)
        XCTAssertEqual(history.first?.state, .submitting)
    }

    func testReconciliationRequiresExactCloidAndOrderTerms() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let (journal, quote, id) = try await context.submitting()
        _ = try await journal.recordOrderResponse(id: id, response: nil, wallet: F.wallet)
        for overrides in [["cloid": "0x00000000000000000000000000000099"], ["side": "A"], ["origSz": "1"], ["coin": "NVDA"]] {
            let data = try context.status(quote.order, overrides: overrides)
            await expectJournalFailure { try await journal.reconcileOrder(id: id, response: data, wallet: F.wallet) }
        }
        await expectJournalFailure {
            try await journal.reconcileOrder(id: id, response: Data(#"{"status":"unknownOid"}"#.utf8), wallet: F.wallet)
        }
        let reconciled = try await journal.reconcileOrder(id: id, response: context.status(quote.order), wallet: F.wallet)
        XCTAssertEqual(reconciled.state, .reconciled)
        XCTAssertEqual(reconciled.reconciledStatus?.status, "filled")
        XCTAssertNil(reconciled.acknowledgement, "A status response must not fabricate an average fill price")
    }

    func testMarketSizingNeverRoundsPastSlippageLimit() throws {
        let snapshot = try Q.snapshot(), market = snapshot.market
        let book = try HyperliquidOrderBook.decode(Q.book(), market: market, now: F.now)
        let buy = try HyperliquidMarketOrderPlan.order(notional: "100", side: .buy, slippageBPS: 50,
            wallet: F.wallet, snapshot: snapshot, book: book, nonce: 1_789_084_801_000)
        XCTAssertEqual(buy.size.wire, "0.454")
        XCTAssertEqual(buy.limitPrice.wire, "221.1")
        let sell = try HyperliquidMarketOrderPlan.order(notional: "100", side: .sell, slippageBPS: 50,
            wallet: F.wallet, snapshot: snapshot, book: book, nonce: 1_789_084_801_000)
        XCTAssertEqual(sell.limitPrice.wire, "217.91")
        for bad in ["0", "9.99", "100.0000001", "NaN", "-10"] {
            XCTAssertThrowsError(try HyperliquidMarketOrderPlan.order(notional: bad, side: .buy, slippageBPS: 50,
                wallet: F.wallet, snapshot: snapshot, book: book, nonce: 1_789_084_801_000))
        }
    }
}

struct OrderLifecycleContext: Sendable {
    typealias F = HyperliquidTradingFixture
    typealias Q = HyperliquidQuoteFixture
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("order-test-" + UUID().uuidString)
    let keychain = JournalTestKeychain()
    let clock = TradingCheckClock()
    func cleanup() { try? FileManager.default.removeItem(at: directory) }
    func journal(probe: @escaping @Sendable (FundingJournalCommitPhase) throws -> Void = { _ in }) throws -> FundingTransactionJournal {
        try .init(directory: directory, service: "order-test", keychain: keychain, clock: { clock.now }, commitProbe: probe)
    }
    func preview() async throws -> HyperliquidOrderPreview {
        try await HyperliquidOrderPreviewProvider(reader: TradingCheckReaderStub([Q.fees(), Q.book()]),
            clock: { clock.now }, continuousClock: { clock.instant }).preview(order: Q.order(), wallet: F.wallet,
                account: Q.snapshot(clock: clock), reviewedLeverage: 10, reviewedMarginMode: .cross)
    }
    func signature(_ order: HyperliquidOrderIntent) throws -> String {
        let key = try XCTUnwrap(PrivateKey(data: Data(repeating: 0, count: 31) + Data([1])))
        let value = EthereumMessageSigner.signTypedMessage(privateKey: key, messageJson: try HyperliquidOrderCodec.typedJSON(order))
        return value.hasPrefix("0x") ? value : "0x" + value
    }
    func lease() -> FundingSigningLease {
        .init(wallet: F.wallet, clock: { clock.now }, continuousNow: { clock.instant })
    }
    func signed() async throws -> (FundingTransactionJournal, HyperliquidOrderPreview, UUID) {
        let journal = try journal(), quote = try await preview(), id = UUID()
        _ = try await journal.reserveOrder(id: id, preview: quote, wallet: F.wallet, continuousNow: clock.instant)
        _ = try await journal.beginOrderSigning(id: id, preview: quote, wallet: F.wallet, continuousNow: clock.instant)
        _ = try await journal.recordOrderSignature(id: id, signature: signature(quote.order), wallet: F.wallet)
        return (journal, quote, id)
    }
    func permit() async throws -> (FundingTransactionJournal, HyperliquidOrderPreview, UUID, HyperliquidOrderSubmissionPermit) {
        let (journal, quote, id) = try await signed()
        let permit = try await journal.beginOrderSubmission(id: id, preview: quote, wallet: F.wallet, continuousClock: { clock.instant })
        return (journal, quote, id, permit)
    }
    func submitting() async throws -> (FundingTransactionJournal, HyperliquidOrderPreview, UUID) {
        let (journal, quote, id, _) = try await permit()
        return (journal, quote, id)
    }
    func status(_ order: HyperliquidOrderIntent, overrides: [String: String] = [:]) throws -> Data {
        var row: [String: Any] = ["coin": order.market.coin, "side": "B", "limitPx": order.limitPrice.wire,
            "sz": "0", "origSz": order.size.wire, "tif": "Ioc", "cloid": order.cloid, "oid": 25,
            "timestamp": order.nonce, "reduceOnly": order.reduceOnly, "isTrigger": false, "children": []]
        row.merge(overrides) { _, next in next }
        return try F.data(["status": "order", "order": ["order": row, "status": "filled", "statusTimestamp": order.nonce]])
    }
}
