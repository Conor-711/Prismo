import XCTest
@testable import BSmart

@MainActor
final class HyperCoreBalanceStoreTests: XCTestCase {
    func testRegistrationMustMatchBeforeSendingOwnerToPublicAPI() async {
        for variant in 0...2 {
            let service = HistoryAccountStub(wallet: CoreBalanceFixture.wallet)
            if variant == 0 { service.walletAccountID = nil }
            if variant == 1 { service.registeredAccountID = UUID() }
            if variant == 2 { service.afterRegistration = { service.walletAccountID = UUID() } }
            let provider = ControlledCoreBalances()
            let store = HyperCoreBalanceStore(service: service, provider: provider)
            await store.refresh(wallet: CoreBalanceFixture.wallet)
            let count = await provider.count
            XCTAssertEqual(count, 0); XCTAssertNil(store.snapshot); XCTAssertNotNil(store.errorMessage)
        }
    }

    func testFailureClearsOldDataAndDoesNotDisplayZero() async throws {
        let (store, provider, _) = makeStore()
        let first = Task { await store.refresh(wallet: CoreBalanceFixture.wallet) }
        await wait(1, provider); await provider.complete(0, .success(try CoreBalanceFixture.snapshot()))
        await first.value; XCTAssertNotNil(store.snapshot)
        let second = Task { await store.refresh(wallet: CoreBalanceFixture.wallet) }
        await wait(2, provider); XCTAssertNil(store.snapshot)
        await provider.complete(1, .failure(HyperCoreBalanceError.unavailable)); await second.value
        XCTAssertNil(store.snapshot); XCTAssertNotNil(store.errorMessage); XCTAssertFalse(store.isLoading)
    }

    func testLateCompletionCannotSurviveClearCancellationOrLogout() async throws {
        for variant in 0...2 {
            let (store, provider, service) = makeStore()
            let request = Task { await store.refresh(wallet: CoreBalanceFixture.wallet) }
            await wait(1, provider)
            if variant == 0 { store.clear() }
            if variant == 1 { request.cancel() }
            if variant == 2 { service.walletAccountID = nil }
            await provider.complete(0, .success(try CoreBalanceFixture.snapshot())); await request.value
            XCTAssertNil(store.snapshot); XCTAssertFalse(store.isLoading)
            if variant != 2 { XCTAssertNil(store.errorMessage) }
        }
    }

    func testOutOfOrderAndExpiredCompletionsCannotBecomeCurrent() async throws {
        let (store, provider, _) = makeStore()
        let first = Task { await store.refresh(wallet: CoreBalanceFixture.wallet) }
        await wait(1, provider)
        let second = Task { await store.refresh(wallet: CoreBalanceFixture.wallet) }
        await wait(2, provider)
        await provider.complete(1, .success(try CoreBalanceFixture.snapshot(mode: .portfolioMargin))); await second.value
        await provider.complete(0, .success(try CoreBalanceFixture.snapshot())); await first.value
        XCTAssertEqual(store.snapshot?.mode, .portfolioMargin)
        let third = Task { await store.refresh(wallet: CoreBalanceFixture.wallet) }
        await wait(3, provider)
        await provider.complete(2, .success(try CoreBalanceFixture.snapshot(time: CoreBalanceFixture.now.addingTimeInterval(-31))))
        await third.value; XCTAssertNil(store.snapshot); XCTAssertNotNil(store.errorMessage)
    }

    func testPreviouslyLoadedBalanceIsHiddenWhenSessionExpiresOrWalletChanges() async throws {
        let (store, provider, service) = makeStore()
        let request = Task { await store.refresh(wallet: CoreBalanceFixture.wallet) }
        await wait(1, provider); await provider.complete(0, .success(try CoreBalanceFixture.snapshot()))
        await request.value
        XCTAssertNotNil(store.currentSnapshot(wallet: CoreBalanceFixture.wallet, now: CoreBalanceFixture.now))
        XCTAssertNil(store.currentSnapshot(wallet: CoreBalanceFixture.wallet, now: CoreBalanceFixture.now.addingTimeInterval(30)))
        let foreignWallet = DeviceWalletSummary(accountID: UUID(), address: CoreBalanceFixture.wallet.address, recoveryVerified: true)
        XCTAssertNil(store.currentSnapshot(wallet: foreignWallet, now: CoreBalanceFixture.now))
        service.walletAccountID = nil
        XCTAssertNil(store.currentSnapshot(wallet: CoreBalanceFixture.wallet, now: CoreBalanceFixture.now))
    }

    func testForeignProviderSnapshotCannotBecomeCurrent() async throws {
        let (store, provider, _) = makeStore()
        let request = Task { await store.refresh(wallet: CoreBalanceFixture.wallet) }
        await wait(1, provider)
        let original = try CoreBalanceFixture.snapshot()
        let foreign = HyperCoreBalanceSnapshot(accountID: UUID(), owner: original.owner, mode: original.mode,
            usdc: original.usdc, held: original.held, perps: original.perps, requestedAt: original.requestedAt, checkedAt: original.checkedAt)
        await provider.complete(0, .success(foreign)); await request.value
        XCTAssertNil(store.snapshot); XCTAssertNotNil(store.errorMessage)
    }

    private func makeStore() -> (HyperCoreBalanceStore, ControlledCoreBalances, HistoryAccountStub) {
        let service = HistoryAccountStub(wallet: CoreBalanceFixture.wallet), provider = ControlledCoreBalances()
        return (HyperCoreBalanceStore(service: service, provider: provider, clock: { CoreBalanceFixture.now }), provider, service)
    }
    private func wait(_ expected: Int, _ provider: ControlledCoreBalances) async {
        for _ in 0..<1_000 { if await provider.count >= expected { return }; await Task.yield() }
        XCTFail("Balance read did not start")
    }
}

private actor ControlledCoreBalances: HyperCoreBalanceProviding {
    private(set) var count = 0
    private var pending: [Int: CheckedContinuation<HyperCoreBalanceSnapshot, Error>] = [:]
    func snapshot(wallet: DeviceWalletSummary) async throws -> HyperCoreBalanceSnapshot {
        try await withCheckedThrowingContinuation { pending[count] = $0; count += 1 }
    }
    func complete(_ index: Int, _ result: Result<HyperCoreBalanceSnapshot, Error>) { pending.removeValue(forKey: index)?.resume(with: result) }
}
