import XCTest
@testable import BSmart

@MainActor
final class FundingSourceHistoryStoreTests: XCTestCase {
    func testQueryIsExplicitAndRequiresFreshRegistration() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let journal = try context.journal(); let id = UUID()
        _ = try await context.ready(context.transaction(), id: id, journal: journal)
        context.clock.advance(120)
        let observer = HistoryObserverStub(now: context.clock.now)
        let service = HistoryAccountStub(wallet: context.wallet)
        let store = FundingHistoryStore(service: service, journal: journal, observer: observer)
        await store.refresh(wallet: context.wallet)
        XCTAssertEqual(observer.reads, 0)
        await store.checkSource(id: UUID(), wallet: context.wallet)
        XCTAssertEqual(observer.reads, 0)
        await store.checkSource(id: id, wallet: context.wallet)
        XCTAssertEqual(observer.reads, 1)
        XCTAssertEqual(service.reads, 2)
        XCTAssertEqual(store.entries.first?.stage, .sourceExecuted)
        service.registeredAccountID = UUID()
        await store.checkSource(id: id, wallet: context.wallet)
        XCTAssertEqual(observer.reads, 1)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(store.errorMessage, FundingObservationError.unavailable.errorDescription)
    }

    func testQueryFailureClearsStaleDisplayButPreservesDurableEvidence() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let journal = try context.journal(); let id = UUID()
        _ = try await context.ready(context.transaction(), id: id, journal: journal)
        context.clock.advance(120)
        let observer = HistoryObserverStub(now: context.clock.now)
        let store = FundingHistoryStore(service: HistoryAccountStub(wallet: context.wallet), journal: journal, observer: observer)
        await store.refresh(wallet: context.wallet)
        await store.checkSource(id: id, wallet: context.wallet)
        observer.fails = true
        await store.checkSource(id: id, wallet: context.wallet)
        XCTAssertFalse(store.didLoad)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(store.errorMessage, FundingObservationError.unavailable.errorDescription)
        let history = try await journal.history(wallet: context.wallet)
        XCTAssertEqual(history.first?.stage, .sourceExecuted)
        await store.refresh(wallet: context.wallet)
        XCTAssertEqual(store.entries.first?.stage, .sourceExecuted)
        XCTAssertEqual(observer.reads, 2)
    }

    func testVerifiedCompletionIsArchivedAfterDepartureAccountChangeOrCancellation() async throws {
        for mode in 0...2 {
            let context = FundingJournalTestContext(); defer { context.cleanup() }
            let journal = try context.journal(); let id = UUID()
            _ = try await context.ready(context.transaction(), id: id, journal: journal)
            context.clock.advance(120)
            let observer = HistoryObserverStub(now: context.clock.now)
            let service = HistoryAccountStub(wallet: context.wallet)
            let store = FundingHistoryStore(service: service, journal: journal, observer: observer)
            await store.refresh(wallet: context.wallet)
            var operation: Task<Void, Never>?
            observer.beforeReturn = {
                switch mode {
                case 0: store.clear()
                case 1: service.walletAccountID = UUID()
                default: operation?.cancel()
                }
            }
            operation = Task { await store.checkSource(id: id, wallet: context.wallet) }
            await operation?.value
            XCTAssertTrue(store.entries.isEmpty)
            XCTAssertFalse(store.didLoad)
            let stored = try await journal.sourceLookup(id: id, wallet: context.wallet)
            XCTAssertNotNil(stored.previous)
            XCTAssertEqual(stored.previous?.receipt?.succeeded, true)
        }
    }
}

@MainActor
private final class HistoryObserverStub: FundingSourceObserving {
    let now: Date
    var reads = 0
    var fails = false
    var beforeReturn: (() -> Void)?
    init(now: Date) { self.now = now }
    func observe(_ lookup: FundingSourceLookup, wallet: DeviceWalletSummary) async throws -> FundingSourceObservation {
        reads += 1
        if fails { throw FundingPreflightError.unavailable }
        let fixture = FundingObservationFixture(record: lookup.record, now: now)
        let result = try await fixture.observer(rpc: FundingObservationRPC(fixture)).observe(lookup, wallet: wallet)
        beforeReturn?()
        return result
    }
}
