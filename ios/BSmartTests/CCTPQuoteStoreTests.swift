import XCTest
@testable import BSmart

@MainActor
final class CCTPQuoteStoreTests: XCTestCase {
    func testFailureClearsPreviousQuoteInsteadOfPretendingZeroFees() async {
        let provider = ControlledFeeProvider()
        let store = CCTPQuoteStore(client: provider)
        let first = Task { await store.refresh() }
        await waitForRequests(1, provider: provider)
        await provider.complete(0, result: .success(schedule()))
        await first.value
        XCTAssertNotNil(store.schedule)
        let second = Task { await store.refresh() }
        await waitForRequests(2, provider: provider)
        XCTAssertNil(store.schedule)
        XCTAssertTrue(store.isLoading)
        await provider.complete(1, result: .failure(CCTPFundingError.unavailable))
        await second.value
        XCTAssertNil(store.schedule)
        XCTAssertEqual(store.error, .unavailable)
        XCTAssertFalse(store.isLoading)
    }

    func testOlderResultCannotOverwriteMoreRecentResponse() async {
        let provider = ControlledFeeProvider()
        let store = CCTPQuoteStore(client: provider)
        let first = Task { await store.refresh() }
        await waitForRequests(1, provider: provider)
        let second = Task { await store.refresh() }
        await waitForRequests(2, provider: provider)
        await provider.complete(1, result: .success(schedule(fee: 300_000)))
        await second.value
        await provider.complete(0, result: .success(schedule(fee: 200_000)))
        await first.value
        XCTAssertEqual(store.schedule?.forwardingFeeUnits, 300_000)
    }

    func testLeavingPageInvalidatesInFlightResponse() async {
        let provider = ControlledFeeProvider()
        let store = CCTPQuoteStore(client: provider)
        let request = Task { await store.refresh() }
        await waitForRequests(1, provider: provider)
        store.clear()
        await provider.complete(0, result: .success(schedule()))
        await request.value
        XCTAssertNil(store.schedule)
        XCTAssertNil(store.error)
        XCTAssertFalse(store.isLoading)
    }

    func testExpiredProviderResponseRejected() async {
        let provider = ControlledFeeProvider()
        let store = CCTPQuoteStore(client: provider)
        let request = Task { await store.refresh() }
        await waitForRequests(1, provider: provider)
        let stale = CCTPFeeSchedule(protocolRateMillionths: 0, forwardingFeeUnits: 200_000,
            receivedAt: Date().addingTimeInterval(-61))
        await provider.complete(0, result: .success(stale))
        await request.value
        XCTAssertNil(store.schedule)
        XCTAssertEqual(store.error, .expiredQuote)
    }

    private func schedule(fee: UInt64 = 200_000) -> CCTPFeeSchedule {
        .init(protocolRateMillionths: 0, forwardingFeeUnits: fee, receivedAt: Date())
    }

    private func waitForRequests(_ expected: Int, provider: ControlledFeeProvider) async {
        for _ in 0..<1000 {
            if await provider.count >= expected { return }
            await Task.yield()
        }
        XCTFail("Fee request did not start")
    }
}

private actor ControlledFeeProvider: CCTPFeeProviding {
    private var requests: [Int: CheckedContinuation<CCTPFeeSchedule, Error>] = [:]
    private(set) var count = 0
    func schedule() async throws -> CCTPFeeSchedule {
        try await withCheckedThrowingContinuation { continuation in
            requests[count] = continuation
            count += 1
        }
    }
    func complete(_ index: Int, result: Result<CCTPFeeSchedule, Error>) {
        requests.removeValue(forKey: index)?.resume(with: result)
    }
}
