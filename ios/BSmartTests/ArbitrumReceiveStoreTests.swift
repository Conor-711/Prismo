import XCTest
@testable import BSmart

@MainActor
final class ArbitrumReceiveStoreTests: XCTestCase {
    func testVerifiedAddressUsesExactOwnerWithChecksum() async throws {
        let service = ReceiveWalletService()
        let store = ArbitrumReceiveStore(service: service)
        await store.refresh(context: service.context)
        XCTAssertEqual(service.reads, 1)
        XCTAssertEqual(store.currentAddress(context: service.context)?.value,
                       "0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf")
        XCTAssertTrue(store.hasChecked)
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(store.isLoading)
    }

    func testDisabledMissingInvalidAndUnconfirmedNeverQueryOrExposeAddress() async {
        let service = ReceiveWalletService()
        let unbacked = DeviceWalletSummary(accountID: service.wallet.accountID,
            address: "0x0", recoveryVerified: false)
        let contexts = [
            ArbitrumReceiveContext(wallet: service.wallet, depositsEnabled: false, networkConfirmed: true),
            .init(wallet: nil, depositsEnabled: true, networkConfirmed: true),
            .init(wallet: unbacked, depositsEnabled: true, networkConfirmed: true),
            .init(wallet: service.wallet, depositsEnabled: true, networkConfirmed: false)
        ]
        for context in contexts {
            let store = ArbitrumReceiveStore(service: service)
            await store.refresh(context: context)
            XCTAssertNil(store.currentAddress(context: context))
            XCTAssertFalse(store.hasChecked)
        }
        XCTAssertEqual(service.reads, 0)
    }

    func testUnbackedInternalWalletReceivesOnlyAfterRegistryAndNetworkChecks() async {
        let service = ReceiveWalletService()
        let wallet = DeviceWalletSummary(accountID: service.wallet.accountID, address: service.wallet.address, recoveryVerified: false)
        let context = ArbitrumReceiveContext(wallet: wallet, depositsEnabled: true, networkConfirmed: true)
        let store = ArbitrumReceiveStore(service: service)
        await store.refresh(context: context)
        XCTAssertEqual(store.currentAddress(context: context)?.value, "0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf")
        XCTAssertEqual(service.reads, 1)
        service.result = .init(accountId: wallet.accountID, address: nil)
        await store.refresh(context: context)
        XCTAssertNil(store.currentAddress(context: context))
        XCTAssertFalse(wallet.recoveryVerified)
    }

    func testMissingSessionNeverQueries() async {
        let service = ReceiveWalletService()
        service.walletAccountID = nil
        let store = ArbitrumReceiveStore(service: service)
        await store.refresh(context: service.context)
        XCTAssertEqual(service.reads, 0)
        XCTAssertNil(store.currentAddress(context: service.context))
    }

    func testUnboundWrongOwnerAndWrongAccountRejectRegistration() async {
        let service = ReceiveWalletService()
        for registration in [
            TradingWalletRegistration(accountId: service.wallet.accountID, address: nil),
            .init(accountId: service.wallet.accountID, address: "0x" + String(repeating: "2", count: 40)),
            .init(accountId: UUID(), address: service.wallet.address)
        ] {
            service.result = registration
            let store = ArbitrumReceiveStore(service: service)
            await store.refresh(context: service.context)
            XCTAssertNil(store.currentAddress(context: service.context))
            XCTAssertNotNil(store.errorMessage)
            XCTAssertFalse(store.isLoading)
        }
    }

    func testFailureClearsEarlierSuccessAndDoesNotExposeRawError() async {
        let service = ReceiveWalletService()
        let store = ArbitrumReceiveStore(service: service)
        await store.refresh(context: service.context)
        XCTAssertNotNil(store.currentAddress(context: service.context))
        service.fail = true
        await store.refresh(context: service.context)
        XCTAssertNil(store.currentAddress(context: service.context))
        XCTAssertNotNil(store.errorMessage)
        XCTAssertFalse(store.errorMessage?.contains("private-server-detail") ?? true)
    }

    func testCurrentContextRecheckedBeforeDisplayAndCopy() async {
        let service = ReceiveWalletService()
        let store = ArbitrumReceiveStore(service: service)
        await store.refresh(context: service.context)
        for context in [
            ArbitrumReceiveContext(wallet: service.wallet, depositsEnabled: false, networkConfirmed: true),
            .init(wallet: service.wallet, depositsEnabled: true, networkConfirmed: false),
            .init(wallet: .init(accountID: service.wallet.accountID, address: service.wallet.address,
                                recoveryVerified: false), depositsEnabled: true, networkConfirmed: true),
            .init(wallet: .init(accountID: service.wallet.accountID, address: "0x" + String(repeating: "2", count: 40),
                                recoveryVerified: true), depositsEnabled: true, networkConfirmed: true)
        ] { XCTAssertNil(store.currentAddress(context: context)) }
        service.walletAccountID = UUID()
        XCTAssertNil(store.currentAddress(context: service.context))
    }

    func testWallClockExpiresAtSixtySecondsAndRejectsRollback() async {
        let service = ReceiveWalletService()
        let base = Date()
        var now = base
        let store = ArbitrumReceiveStore(service: service, now: { now })
        await store.refresh(context: service.context)
        now = base.addingTimeInterval(59.9)
        XCTAssertNotNil(store.currentAddress(context: service.context))
        now = base.addingTimeInterval(60)
        XCTAssertNil(store.currentAddress(context: service.context))
        now = base.addingTimeInterval(-1)
        XCTAssertNil(store.currentAddress(context: service.context))
    }

    func testContinuousClockExpiresEvenWhenSystemDateIsFrozen() async {
        let service = ReceiveWalletService()
        let date = Date(), base = ContinuousClock.now
        var instant = base
        let store = ArbitrumReceiveStore(service: service, now: { date }, continuousNow: { instant })
        await store.refresh(context: service.context)
        instant = base.advanced(by: .seconds(60))
        XCTAssertNil(store.currentAddress(context: service.context))
        instant = base.advanced(by: .seconds(-1))
        XCTAssertNil(store.currentAddress(context: service.context))
    }

    func testRegistrationLatencyCountsTowardExpiry() async {
        let service = ReceiveWalletService()
        var now = Date()
        service.beforeReturn = { now = now.addingTimeInterval(60) }
        let store = ArbitrumReceiveStore(service: service, now: { now })
        await store.refresh(context: service.context)
        XCTAssertNil(store.currentAddress(context: service.context))
        XCTAssertNotNil(store.errorMessage)
    }

    func testAccountChangeWhileWaitingRejectsLateResult() async {
        let service = ReceiveWalletService()
        service.beforeReturn = { service.walletAccountID = UUID() }
        let store = ArbitrumReceiveStore(service: service)
        await store.refresh(context: service.context)
        XCTAssertNil(store.currentAddress(context: service.context))
    }

    func testClearRejectsLateResponse() async {
        let service = ReceiveWalletService()
        let store = ArbitrumReceiveStore(service: service)
        service.beforeReturn = { store.clear() }
        await store.refresh(context: service.context)
        XCTAssertNil(store.currentAddress(context: service.context))
        XCTAssertFalse(store.hasChecked)
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(store.isLoading)
    }

    func testCancelledTaskDoesNotExposeAddress() async {
        let service = ReceiveWalletService()
        let store = ArbitrumReceiveStore(service: service)
        let task = Task { await store.refresh(context: service.context) }
        task.cancel()
        await task.value
        XCTAssertNil(store.currentAddress(context: service.context))
        XCTAssertFalse(store.isLoading)
    }

    func testOlderRequestCannotReplaceNewerCheck() async {
        let service = ReceiveWalletService()
        let store = ArbitrumReceiveStore(service: service)
        service.shouldSuspend = true
        let first = Task { await store.refresh(context: service.context) }
        for _ in 0..<100 where service.waiter == nil { await Task.yield() }
        XCTAssertNotNil(service.waiter)
        service.shouldSuspend = false
        await store.refresh(context: service.context)
        XCTAssertNotNil(store.currentAddress(context: service.context))
        service.waiter?.resume(returning: .init(accountId: UUID(), address: nil))
        service.waiter = nil
        await first.value
        XCTAssertNotNil(store.currentAddress(context: service.context))
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(store.isLoading)
    }
}

@MainActor
final class ReceiveWalletService: AccountWalletServicing {
    let wallet = DeviceWalletSummary(accountID: UUID(), address: "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf",
                                     recoveryVerified: true)
    var walletAccountID: UUID?
    var result: TradingWalletRegistration?
    var fail = false
    var reads = 0
    var beforeReturn: (() -> Void)?
    var shouldSuspend = false
    var waiter: CheckedContinuation<TradingWalletRegistration, Never>?
    var context: ArbitrumReceiveContext { .init(wallet: wallet, depositsEnabled: true, networkConfirmed: true) }

    init() { walletAccountID = wallet.accountID }
    func walletRegistration() async throws -> TradingWalletRegistration {
        reads += 1
        if shouldSuspend { return await withCheckedContinuation { waiter = $0 } }
        beforeReturn?()
        if fail { throw NSError(domain: "private-server-detail", code: 1) }
        return result ?? .init(accountId: wallet.accountID, address: wallet.address)
    }
    func walletChallenge(address: String) async throws -> TradingWalletChallenge {
        XCTFail("Receive must never sign or bind"); throw DeviceWalletError.invalidProof
    }
    func bindWallet(challenge: TradingWalletChallenge, signature: String) async throws -> TradingWalletRegistration {
        XCTFail("Receive must never sign or bind"); throw DeviceWalletError.invalidProof
    }
}
