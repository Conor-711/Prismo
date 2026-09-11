import XCTest
@testable import BSmart

@MainActor
final class HyperliquidFillRecoveryTests: XCTestCase {
    typealias F = OrderFillFixture

    func testClosedOrderLoadsActualFeesWithoutSigningOrResending() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let (journal, _, id) = try await context.submitting()
        let record = try await journal.recordOrderResponse(id: id, response: F.ack(), wallet: F.wallet)
        let reader = FillRecoveryReader([try F.data([F.row(), F.row(["tid": 2, "sz": "1.5", "px": "220", "fee": "0.02"])])])
        let store = make(context, journal: journal, reader: reader)
        await store.reconcile(record, wallet: F.wallet)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.result?.state, .filled)
        XCTAssertEqual(store.fills[id]?.quantity.wire, "2.5")
        XCTAssertEqual(store.fills[id]?.averagePrice?.wire, "219.6")
        XCTAssertEqual(store.fills[id]?.fee, "0.03")
        XCTAssertEqual(store.fills[id]?.complete, true)
        let reads = await reader.queries
        XCTAssertEqual(reads.count, 1)
        guard case .fills(let owner, let start, let end) = reads[0] else { return XCTFail("Expected read-only fill query") }
        XCTAssertEqual(owner, F.wallet.address)
        XCTAssertEqual(start, record.order.nonce - 2000)
        XCTAssertEqual(end, record.order.expiresAfter + 2000)
        let resumed = make(context, journal: try context.journal(), reader: FillRecoveryReader([]))
        await resumed.loadHistory(wallet: F.wallet)
        XCTAssertEqual(resumed.fills[id]?.fee, "0.03")
    }

    func testStaleUIRecordUsesAlreadyRecoveredJournalInsteadOfSecondStatusTransition() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let (journal, quote, id) = try await context.submitting()
        let stale = try await journal.recordOrderResponse(id: id, response: nil, wallet: F.wallet)
        _ = try await journal.reconcileOrder(id: id, response: context.status(quote.order), wallet: F.wallet)
        let reader = FillRecoveryReader([try F.data([F.row(["sz": "2.5"])])])
        let store = make(context, journal: journal, reader: reader)
        await store.reconcile(stale, wallet: F.wallet)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.result?.state, .reconciled)
        XCTAssertEqual(store.fills[id]?.complete, true)
        let queries = await reader.queries
        XCTAssertEqual(queries.count, 1)
        guard case .fills = queries[0] else { return XCTFail("Stale UI must not request another status transition") }
    }

    func testLostAcknowledgementRequiresStatusBeforeReadingFees() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let (journal, quote, id) = try await context.submitting()
        let record = try await journal.recordOrderResponse(id: id, response: nil, wallet: F.wallet)
        let reader = FillRecoveryReader([try context.status(quote.order), try F.data([F.row(["sz": "2.5"])])])
        let store = make(context, journal: journal, reader: reader)
        await store.reconcile(record, wallet: F.wallet)
        XCTAssertEqual(store.result?.state, .reconciled)
        XCTAssertEqual(store.fills[id]?.complete, true)
        let queries = await reader.queries
        XCTAssertEqual(queries.count, 2)
        XCTAssertEqual(queries.first, .orderStatus(owner: F.wallet.address, cloid: record.order.cloid))
    }

    func testReadFailurePreservesAcceptedOrderAndKnownFeeSubtotal() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let (journal, _, id) = try await context.submitting()
        let record = try await journal.recordOrderResponse(id: id, response: F.ack(), wallet: F.wallet)
        try await journal.recordOrderFills(id: id, response: F.data([F.row()]), wallet: F.wallet)
        let store = make(context, journal: journal, reader: FillRecoveryReader([]))
        await store.reconcile(record, wallet: F.wallet)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(store.result?.state, .filled)
        XCTAssertEqual(store.fills[id]?.fee, "0.01")
        XCTAssertEqual(store.fills[id]?.complete, false)
    }

    func testWrongAccountCannotReadOrDisplayOrderHistory() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let (journal, _, id) = try await context.submitting()
        let record = try await journal.recordOrderResponse(id: id, response: F.ack(), wallet: F.wallet)
        let service = OrderStoreAccount(clock: context.clock)
        service.walletAccountID = UUID()
        let reader = FillRecoveryReader([])
        let store = make(context, journal: journal, reader: reader, service: service)
        await store.reconcile(record, wallet: F.wallet)
        XCTAssertTrue(store.history.isEmpty); XCTAssertTrue(store.fills.isEmpty); XCTAssertNil(store.result)
        let queries = await reader.queries
        XCTAssertTrue(queries.isEmpty)
    }

    func testReturnedEvidencePersistsAfterAccountChangeWithoutLeakingToNewAccount() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let (journal, _, id) = try await context.submitting()
        let record = try await journal.recordOrderResponse(id: id, response: F.ack(), wallet: F.wallet)
        let service = OrderStoreAccount(clock: context.clock)
        let reader = FillRecoveryReader([try F.data([F.row()])]) { await MainActor.run { service.walletAccountID = UUID() } }
        let store = make(context, journal: journal, reader: reader, service: service)
        await store.loadHistory(wallet: F.wallet)
        XCTAssertEqual(store.history.count, 1)
        await store.reconcile(record, wallet: F.wallet)
        XCTAssertNil(store.result); XCTAssertTrue(store.fills.isEmpty); XCTAssertTrue(store.history.isEmpty)
        let restored = try await context.journal().orderFillSummaries(wallet: F.wallet)
        XCTAssertEqual(restored[id]?.fills.count, 1)
    }

    func testStatusRecoverySurvivesWallClockRollback() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let (journal, quote, id) = try await context.submitting()
        let record = try await journal.recordOrderResponse(id: id, response: nil, wallet: F.wallet)
        context.clock.advance(wall: -120, steady: .seconds(1))
        let reader = FillRecoveryReader([try context.status(quote.order), try F.data([F.row(["sz": "2.5"])])])
        let store = make(context, journal: journal, reader: reader)
        await store.reconcile(record, wallet: F.wallet)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.result?.updatedAt, record.updatedAt)
        XCTAssertEqual(store.fills[id]?.complete, true)
    }

    private func make(_ context: OrderLifecycleContext, journal: FundingTransactionJournal,
                      reader: FillRecoveryReader, service: OrderStoreAccount? = nil) -> HyperliquidMarketOrderStore {
        .init(service: service ?? OrderStoreAccount(clock: context.clock), journal: journal, reader: reader,
              signer: NoFillRecoverySigner(), broadcaster: NoFillRecoveryBroadcaster(),
              clock: { context.clock.now }, continuousClock: { context.clock.instant }, enabled: { false })
    }
}

private actor FillRecoveryReader: HyperliquidExecutionReading {
    private var responses: [Data]
    private let onRead: @Sendable () async -> Void
    private(set) var queries: [HyperliquidExecutionQuery] = []
    init(_ responses: [Data], onRead: @escaping @Sendable () async -> Void = {}) {
        self.responses = responses; self.onRead = onRead
    }
    func read(_ query: HyperliquidExecutionQuery) async throws -> Data {
        queries.append(query)
        guard !responses.isEmpty else { throw HyperliquidTradingCheckError.unavailable }
        let data = responses.removeFirst()
        await onRead()
        return data
    }
}

@MainActor
private struct NoFillRecoverySigner: HyperliquidDeviceSigning {
    func signOrder(_ permit: HyperliquidOrderSigningPermit, lease: FundingSigningLease) async throws -> String {
        XCTFail("Read-only fill recovery must not sign")
        throw FundingJournalError.invalidTransition
    }
}

private struct NoFillRecoveryBroadcaster: HyperliquidOrderBroadcasting {
    func submit(_ permit: HyperliquidOrderSubmissionPermit, lease: FundingSigningLease) async throws -> Data? {
        XCTFail("Read-only fill recovery must not resubmit")
        throw FundingJournalError.invalidTransition
    }
}
