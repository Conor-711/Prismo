import XCTest
@testable import BSmart

@MainActor
final class CCTPForwardHistoryTests: XCTestCase {
    func testOnlyExplicitCrossChainCheckWithHashQueriesForwardingAndRegistrationIsRequired() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let (journal, lookup) = try await context.attestationReady()
        let attester = HistoryAttesterStub(context: context)
        // Circle may omit a forward hash even though the nonce was already processed in this block.
        attester.nonceUsed = true
        let forwarder = HistoryForwarderStub(context: context)
        let service = HistoryAccountStub(wallet: context.wallet)
        let source = AttestationSourceStub(now: context.clock.now)
        let store = FundingHistoryStore(service: service, journal: journal, observer: source, attester: attester, forwarder: forwarder)
        await store.refresh(wallet: context.wallet)
        XCTAssertEqual(forwarder.reads, 0)
        await store.checkCrossChain(id: lookup.record.intent.id, wallet: context.wallet)
        XCTAssertEqual(forwarder.reads, 0)
        attester.forwardHash = try ForwardVector.load().hash
        await store.checkCrossChain(id: lookup.record.intent.id, wallet: context.wallet)
        XCTAssertEqual(forwarder.reads, 1)
        XCTAssertEqual(store.entries.first?.forwardingStatus, .perpsRequested)
        XCTAssertEqual(store.entries.first?.stage.requiresReconciliation, true)
        service.registeredAccountID = UUID()
        await store.checkCrossChain(id: lookup.record.intent.id, wallet: context.wallet)
        XCTAssertEqual(forwarder.reads, 1)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertNotNil(store.errorMessage)
    }

    func testFailedForwardingClearsStaleProjectionButKeepsAcceptedEvidence() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let (journal, lookup) = try await context.attestationReady()
        let attester = HistoryAttesterStub(context: context); attester.forwardHash = try ForwardVector.load().hash
        let forwarder = HistoryForwarderStub(context: context)
        let store = FundingHistoryStore(service: HistoryAccountStub(wallet: context.wallet), journal: journal,
            observer: AttestationSourceStub(now: context.clock.now), attester: attester, forwarder: forwarder)
        await store.refresh(wallet: context.wallet)
        await store.checkCrossChain(id: lookup.record.intent.id, wallet: context.wallet)
        XCTAssertEqual(store.entries.first?.forwardingStatus, .perpsRequested)
        forwarder.fails = true
        await store.checkCrossChain(id: lookup.record.intent.id, wallet: context.wallet)
        XCTAssertTrue(store.entries.isEmpty); XCTAssertFalse(store.didLoad)
        XCTAssertEqual(store.errorMessage, "Cross-chain status could not be verified. Do not send another deposit.".bSmartLocalized)
        let history = try await journal.history(wallet: context.wallet)
        XCTAssertNil(history.first?.forwardingStatus)
        let archived = try await journal.forwardingLookup(id: lookup.record.intent.id, wallet: context.wallet)
        XCTAssertNotNil(archived.previous?.receipt)
    }

    func testLateForwardingArchivesBeforeHandlingDepartureLogoutAndCancellation() async throws {
        for mode in 0...2 {
            let context = FundingJournalTestContext(); defer { context.cleanup() }
            let (journal, lookup) = try await context.attestationReady()
            let attester = HistoryAttesterStub(context: context); attester.forwardHash = try ForwardVector.load().hash
            let forwarder = HistoryForwarderStub(context: context)
            let service = HistoryAccountStub(wallet: context.wallet)
            let store = FundingHistoryStore(service: service, journal: journal,
                observer: AttestationSourceStub(now: context.clock.now), attester: attester, forwarder: forwarder)
            await store.refresh(wallet: context.wallet)
            var operation: Task<Void, Never>?
            forwarder.beforeReturn = {
                switch mode {
                case 0: store.clear()
                case 1: service.walletAccountID = nil
                default: operation?.cancel()
                }
            }
            operation = Task { await store.checkCrossChain(id: lookup.record.intent.id, wallet: context.wallet) }
            await operation?.value
            XCTAssertTrue(store.entries.isEmpty); XCTAssertFalse(store.didLoad)
            let archived = try await context.journal().forwardingLookup(id: lookup.record.intent.id, wallet: context.wallet)
            XCTAssertNotNil(archived.previous?.receipt)
        }
    }
}

@MainActor
private final class HistoryForwarderStub: CCTPForwardObserving {
    let context: FundingJournalTestContext
    var reads = 0
    var fails = false
    var beforeReturn: (() -> Void)?
    init(context: FundingJournalTestContext) { self.context = context }
    func observe(_ lookup: CCTPForwardLookup, wallet: DeviceWalletSummary) async throws -> CCTPForwardObservation {
        reads += 1
        if fails { throw FundingPreflightError.unavailable }
        let evidence = try await context.forwarder().observe(lookup, wallet: wallet)
        beforeReturn?()
        return evidence
    }
}
