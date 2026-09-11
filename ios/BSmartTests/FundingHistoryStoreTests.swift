import XCTest
@testable import BSmart

@MainActor
final class FundingHistoryStoreTests: XCTestCase {
    func testReadsOnlyAfterFreshMatchingRegistrationAndCancelsExactReview() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let journal = try context.journal()
        let transaction = try await context.transaction()
        let id = UUID()
        _ = try await journal.beginConsent(id: id, plan: transaction.preflight.plan, wallet: context.wallet)
        let service = HistoryAccountStub(wallet: context.wallet)
        let store = FundingHistoryStore(service: service, journal: journal)
        await store.refresh(wallet: context.wallet)
        XCTAssertTrue(store.didLoad)
        XCTAssertEqual(store.entries.first?.stage, .reviewAuthorization)
        context.clock.advance(600)
        await store.cancelReview(id: id, wallet: context.wallet)
        XCTAssertEqual(store.entries.first?.stage, .cancelled)
        XCTAssertEqual(service.reads, 2)
        await store.cancelReview(id: UUID(), wallet: context.wallet)
        XCTAssertEqual(service.reads, 2)
    }

    func testRegistrationMismatchOrExpiredSessionNeverReadsLocalHistory() async throws {
        let wallet = PreflightTestFixture.wallet
        for expired in [false, true] {
            let service = HistoryAccountStub(wallet: wallet)
            if expired { service.walletAccountID = nil } else { service.registeredAccountID = UUID() }
            let journal = HistoryAccessStub()
            let store = FundingHistoryStore(service: service, journal: journal)
            await store.refresh(wallet: wallet)
            XCTAssertEqual(journal.reads, 0)
            XCTAssertFalse(store.didLoad)
            XCTAssertNotNil(store.errorMessage)
        }
    }

    func testAccountChangeDuringRegistrationDoesNotPublishOrReadHistory() async throws {
        let wallet = PreflightTestFixture.wallet
        let service = HistoryAccountStub(wallet: wallet)
        service.afterRegistration = { service.walletAccountID = UUID() }
        let journal = HistoryAccessStub()
        let store = FundingHistoryStore(service: service, journal: journal)
        await store.refresh(wallet: wallet)
        XCTAssertEqual(journal.reads, 0)
        XCTAssertFalse(store.didLoad)
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testBackgroundOrDepartureDiscardsLateCompletion() async throws {
        let wallet = PreflightTestFixture.wallet
        let service = HistoryAccountStub(wallet: wallet)
        let journal = HistoryAccessStub()
        let store = FundingHistoryStore(service: service, journal: journal)
        journal.afterRead = { store.clear() }
        await store.refresh(wallet: wallet)
        XCTAssertFalse(store.isLoading)
        XCTAssertFalse(store.didLoad)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertNil(store.errorMessage)
    }

    func testFailureClearsOldDataWithoutClaimingNoDeposits() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let transaction = try await context.transaction()
        let consent = try await context.journal().beginConsent(id: UUID(), plan: transaction.preflight.plan, wallet: context.wallet)
        let journal = HistoryAccessStub(entries: [try FundingHistoryEntry(consent: consent)])
        let store = FundingHistoryStore(service: HistoryAccountStub(wallet: context.wallet), journal: journal)
        await store.refresh(wallet: context.wallet)
        XCTAssertEqual(store.entries.count, 1)
        journal.error = .integrity
        await store.refresh(wallet: context.wallet)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertFalse(store.didLoad)
        XCTAssertEqual(store.errorMessage, FundingJournalError.integrity.errorDescription)
    }

    func testForeignOrDuplicateProjectionIsRejected() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let transaction = try await context.transaction()
        let consent = try await context.journal().beginConsent(id: UUID(), plan: transaction.preflight.plan, wallet: context.wallet)
        let entry = try FundingHistoryEntry(consent: consent)
        for duplicate in [false, true] {
            let wallet = duplicate ? context.wallet : DeviceWalletSummary(accountID: UUID(), address: context.wallet.address, recoveryVerified: true)
            let journal = HistoryAccessStub(entries: duplicate ? [entry, entry] : [entry])
            let store = FundingHistoryStore(service: HistoryAccountStub(wallet: wallet), journal: journal)
            await store.refresh(wallet: wallet)
            XCTAssertTrue(store.entries.isEmpty)
            XCTAssertFalse(store.didLoad)
            XCTAssertNotNil(store.errorMessage)
        }
    }
}

@MainActor
final class HistoryAccountStub: AccountWalletServicing {
    var walletAccountID: UUID?
    var registeredAccountID: UUID
    let address: String
    var reads = 0
    var afterRegistration: (() -> Void)?
    init(wallet: DeviceWalletSummary) {
        walletAccountID = wallet.accountID; registeredAccountID = wallet.accountID; address = wallet.address
    }
    func walletRegistration() async throws -> TradingWalletRegistration {
        reads += 1
        let registration = TradingWalletRegistration(accountId: registeredAccountID, address: address)
        afterRegistration?()
        return registration
    }
    func walletChallenge(address: String) async throws -> TradingWalletChallenge { throw FundingJournalError.unavailable }
    func bindWallet(challenge: TradingWalletChallenge, signature: String) async throws -> TradingWalletRegistration {
        throw FundingJournalError.unavailable
    }
}

@MainActor
private final class HistoryAccessStub: FundingHistoryAccessing {
    var entries: [FundingHistoryEntry]
    var error: FundingJournalError?
    var reads = 0
    var afterRead: (() -> Void)?
    init(entries: [FundingHistoryEntry] = []) { self.entries = entries }
    func history(wallet: DeviceWalletSummary) async throws -> [FundingHistoryEntry] {
        reads += 1
        afterRead?()
        if let error { throw error }
        return entries
    }
    func cancelReview(id: UUID, wallet: DeviceWalletSummary) async throws { throw FundingJournalError.invalidTransition }
}
