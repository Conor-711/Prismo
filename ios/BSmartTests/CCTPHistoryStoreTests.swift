import XCTest
@testable import BSmart

@MainActor
final class CCTPHistoryStoreTests: XCTestCase {
    func testExplicitCheckRefreshesSourceAndRegistrationBeforeAttestation() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let (journal, lookup) = try await context.attestationReady()
        let attester = HistoryAttesterStub(context: context)
        let source = AttestationSourceStub(now: context.clock.now)
        let service = HistoryAccountStub(wallet: context.wallet)
        let store = FundingHistoryStore(service: service, journal: journal, observer: source, attester: attester)
        await store.refresh(wallet: context.wallet)
        XCTAssertEqual(source.reads, 0); XCTAssertEqual(attester.reads, 0)
        await store.checkCrossChain(id: UUID(), wallet: context.wallet)
        XCTAssertEqual(source.reads, 0)
        await store.checkCrossChain(id: lookup.record.intent.id, wallet: context.wallet)
        XCTAssertEqual(source.reads, 1); XCTAssertEqual(attester.reads, 1)
        XCTAssertEqual(service.reads, 2)
        XCTAssertNotEqual(attester.sourceID, lookup.source.id)
        XCTAssertEqual(store.entries.first?.attestationStatus, .verified)
        service.registeredAccountID = UUID()
        await store.checkCrossChain(id: lookup.record.intent.id, wallet: context.wallet)
        XCTAssertEqual(source.reads, 1); XCTAssertEqual(attester.reads, 1)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertNotNil(store.errorMessage)
    }

    func testPendingSourceDoesNotFetchCircleAndFailuresClearOldCertification() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let journal = try context.journal(); let id = UUID()
        _ = try await context.ready(context.transaction(), id: id, journal: journal)
        context.clock.advance(120)
        let attester = HistoryAttesterStub(context: context)
        let source = AttestationSourceStub(now: context.clock.now)
        source.pending = true
        let store = FundingHistoryStore(service: HistoryAccountStub(wallet: context.wallet), journal: journal, observer: source, attester: attester)
        await store.refresh(wallet: context.wallet)
        await store.checkCrossChain(id: id, wallet: context.wallet)
        XCTAssertEqual(attester.reads, 0)
        XCTAssertEqual(store.entries.first?.stage, .sourcePending)
        source.pending = false
        await store.checkCrossChain(id: id, wallet: context.wallet)
        XCTAssertEqual(store.entries.first?.attestationStatus, .verified)
        attester.fails = true
        await store.checkCrossChain(id: id, wallet: context.wallet)
        XCTAssertTrue(store.entries.isEmpty); XCTAssertFalse(store.didLoad)
        XCTAssertEqual(store.errorMessage, "Cross-chain status could not be verified. Do not send another deposit.".bSmartLocalized)
        let history = try await journal.history(wallet: context.wallet)
        XCTAssertNil(history.first?.attestationStatus)
        XCTAssertEqual(history.first?.stage, .sourceExecuted)
    }

    func testLateAttestationArchivesAfterDepartureLogoutOrCancellationWithoutResurrectingUI() async throws {
        for mode in 0...2 {
            let context = FundingJournalTestContext(); defer { context.cleanup() }
            let (journal, lookup) = try await context.attestationReady()
            let attester = HistoryAttesterStub(context: context)
            let source = AttestationSourceStub(now: context.clock.now)
            let service = HistoryAccountStub(wallet: context.wallet)
            let store = FundingHistoryStore(service: service, journal: journal, observer: source, attester: attester)
            await store.refresh(wallet: context.wallet)
            var operation: Task<Void, Never>?
            attester.beforeReturn = {
                switch mode {
                case 0: store.clear()
                case 1: service.walletAccountID = nil
                default: operation?.cancel()
                }
            }
            operation = Task { await store.checkCrossChain(id: lookup.record.intent.id, wallet: context.wallet) }
            await operation?.value
            XCTAssertTrue(store.entries.isEmpty); XCTAssertFalse(store.didLoad)
            let restored = try await journal.attestationLookup(id: lookup.record.intent.id, wallet: context.wallet)
            XCTAssertNotNil(restored.previous?.proof)
        }
    }
}

@MainActor
final class HistoryAttesterStub: CCTPAttestationObserving {
    let context: FundingJournalTestContext
    var reads = 0
    var sourceID: UUID?
    var fails = false
    var forwardHash: String?
    var nonceUsed = false
    var beforeReturn: (() -> Void)?
    init(context: FundingJournalTestContext) { self.context = context }
    func observe(_ lookup: CCTPAttestationLookup, wallet: DeviceWalletSummary) async throws -> CCTPAttestationObservation {
        reads += 1; sourceID = lookup.source.id
        if fails { throw FundingPreflightError.unavailable }
        let rpc = AttesterRPCStub(now: context.clock.now, overrides: forwardHash == nil && !nonceUsed ? [:] : ["usedNonces(bytes32)": .string(FundingQuantity(1).abi)])
        let evidence = try await context.attester(.complete(AttestationVector.load().proof(), forwardHash: forwardHash), rpc: rpc).observe(lookup, wallet: wallet)
        beforeReturn?()
        return evidence
    }
}

@MainActor
final class AttestationSourceStub: FundingSourceObserving {
    let now: Date
    var reads = 0
    var pending = false
    init(now: Date) { self.now = now }
    func observe(_ lookup: FundingSourceLookup, wallet: DeviceWalletSummary) async throws -> FundingSourceObservation {
        reads += 1
        let fixture = FundingObservationFixture(record: lookup.record, now: now)
        let overrides: [String: FundingRPCValue] = try pending ? ["transaction": fixture.transaction(pending: true),
            "receipt": .null, "nonce": .string("0x0"), "pending": .string("0x1"), "authorization": .string(FundingQuantity(0).abi)] : [:]
        return try await fixture.observer(rpc: FundingObservationRPC(fixture, overrides: overrides)).observe(lookup, wallet: wallet)
    }
}
