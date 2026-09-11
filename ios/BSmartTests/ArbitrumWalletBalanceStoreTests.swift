import XCTest
@testable import BSmart

@MainActor
final class ArbitrumWalletBalanceStoreTests: XCTestCase {
    func testFailureRemovesOldBalanceInsteadOfFillingZero() async throws {
        let provider = ControlledBalanceProvider()
        let store = ArbitrumWalletBalanceStore(provider: provider)
        let first = Task { await store.refresh(wallet: PreflightTestFixture.wallet) }
        await wait(1, provider)
        await provider.complete(0, .success(try snapshot()))
        await first.value
        XCTAssertNotNil(store.snapshot)
        let next = Task { await store.refresh(wallet: PreflightTestFixture.wallet) }
        await wait(2, provider)
        XCTAssertNil(store.snapshot)
        await provider.complete(1, .failure(FundingPreflightError.unavailable))
        await next.value
        XCTAssertNil(store.snapshot)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertFalse(store.isLoading)
    }

    func testLogoutBackgroundAndPageDepartureInvalidatePendingResults() async throws {
        let provider = ControlledBalanceProvider()
        let store = ArbitrumWalletBalanceStore(provider: provider)
        let request = Task { await store.refresh(wallet: PreflightTestFixture.wallet) }
        await wait(1, provider)
        store.clear()
        await provider.complete(0, .success(try snapshot()))
        await request.value
        XCTAssertNil(store.snapshot)
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(store.isLoading)
    }

    func testOutOfOrderResultCannotOverwriteLatestBalance() async throws {
        let provider = ControlledBalanceProvider()
        let store = ArbitrumWalletBalanceStore(provider: provider)
        let first = Task { await store.refresh(wallet: PreflightTestFixture.wallet) }
        await wait(1, provider)
        let second = Task { await store.refresh(wallet: PreflightTestFixture.wallet) }
        await wait(2, provider)
        await provider.complete(1, .success(try snapshot(units: 20)))
        await second.value
        await provider.complete(0, .success(try snapshot(units: 10)))
        await first.value
        XCTAssertEqual(store.snapshot?.usdc, FundingQuantity(20))
    }

    func testWrongAccountOrStaleResponseIsNotShown() async throws {
        for value in [try snapshot(accountID: UUID()), try snapshot(now: Date().addingTimeInterval(-61))] {
            let provider = ControlledBalanceProvider()
            let store = ArbitrumWalletBalanceStore(provider: provider)
            let request = Task { await store.refresh(wallet: PreflightTestFixture.wallet) }
            await wait(1, provider)
            await provider.complete(0, .success(value))
            await request.value
            XCTAssertNil(store.snapshot)
            XCTAssertNotNil(store.errorMessage)
        }
    }

    private func snapshot(units: UInt64 = 1, accountID: UUID = PreflightTestFixture.wallet.accountID,
                          now: Date = Date()) throws -> ArbitrumWalletSnapshot {
        let block = try ArbitrumFundingBlock(PreflightTestFixture.block(time: now), now: now)
        return .init(accountID: accountID, owner: PreflightTestFixture.wallet.address, block: block,
            usdc: FundingQuantity(units), eth: FundingQuantity(1), nonce: FundingQuantity(0),
            extensionAllowance: FundingQuantity(100), burnLimit: FundingQuantity(100), observedCodeHashes: [:], checkedAt: now)
    }

    private func wait(_ expected: Int, _ provider: ControlledBalanceProvider) async {
        for _ in 0..<1000 {
            if await provider.count >= expected { return }
            await Task.yield()
        }
        XCTFail("Balance request did not start")
    }
}

private actor ControlledBalanceProvider: ArbitrumWalletSnapshotProviding {
    private var pending: [Int: CheckedContinuation<ArbitrumWalletSnapshot, Error>] = [:]
    private(set) var count = 0
    func snapshot(wallet: DeviceWalletSummary) async throws -> ArbitrumWalletSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            pending[count] = continuation
            count += 1
        }
    }
    func complete(_ index: Int, _ result: Result<ArbitrumWalletSnapshot, Error>) {
        pending.removeValue(forKey: index)?.resume(with: result)
    }
}
