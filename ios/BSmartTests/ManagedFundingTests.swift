import XCTest
@testable import BSmart

@MainActor
final class ManagedFundingTests: XCTestCase {
    func testNetworkTabsUseSupportedSourceOrder() {
        XCTAssertEqual(ManagedFundingNetwork.allCases, [.monad, .arbitrum, .base, .ethereum, .bnb])
        XCTAssertEqual(ManagedFundingNetwork.bnb.depositAsset, "Binance-Peg USDC (BEP-20)")
        XCTAssertEqual(ManagedFundingNetwork.ethereum.logoAsset, "FundingChain_Ethereum")
    }

    func testNetworkChangeWhileAvailabilityIsLoadingDoesNotDiscardResult() async {
        let service = FundingServiceFixture()
        let store = ManagedFundingStore(service: service)
        service.beforeAvailabilityReturn = {
            XCTAssertTrue(store.isCheckingAvailability)
            for _ in 0..<3 { store.invalidateAddress() }
        }
        await store.load(wallet: service.wallet)
        XCTAssertTrue(store.available)
        XCTAssertFalse(store.isCheckingAvailability)
        await store.prepare(wallet: service.wallet, network: .arbitrum)
        XCTAssertNotNil(store.address)
    }

    func testInputChangesPreserveAvailabilityErrorAndRetryCanRecover() async {
        let service = FundingServiceFixture()
        let store = ManagedFundingStore(service: service)
        service.enabled = false
        await store.load(wallet: service.wallet)
        store.invalidateAddress()
        XCTAssertNotNil(store.errorMessage)
        service.enabled = true
        service.beforeAvailabilityReturn = { store.invalidateAddress() }
        await store.load(wallet: service.wallet)
        XCTAssertTrue(store.available)
        XCTAssertNil(store.errorMessage)
    }

    func testClearingOrChangingAccountDiscardsLateAvailability() async {
        for changeAccount in [false, true] {
            let service = FundingServiceFixture()
            let store = ManagedFundingStore(service: service)
            service.beforeAvailabilityReturn = {
                if changeAccount { service.accountID = UUID() } else { store.clear() }
            }
            await store.load(wallet: service.wallet)
            XCTAssertFalse(store.available)
            XCTAssertFalse(store.isCheckingAvailability)
        }
    }

    func testInputChangeDiscardsInFlightQuoteWithoutDisablingService() async {
        let service = FundingServiceFixture()
        let store = ManagedFundingStore(service: service)
        await store.load(wallet: service.wallet)
        service.beforeReturn = { store.invalidateAddress() }
        await store.prepare(wallet: service.wallet, network: .arbitrum)
        XCTAssertNil(store.address)
        XCTAssertTrue(store.available)
        XCTAssertFalse(store.isLoading)
    }

    func testProviderDisabledNeverRequestsAddress() async {
        let service = FundingServiceFixture()
        service.enabled = false
        let store = ManagedFundingStore(service: service)
        await store.load(wallet: service.wallet)
        await store.prepare(wallet: service.wallet, network: .arbitrum)
        XCTAssertFalse(store.available)
        XCTAssertEqual(service.addressCount, 0)
        XCTAssertNil(store.address)
    }

    func testAddressRequiresMatchingOwnerNetworkAndValidCreationTime() throws {
        let service = FundingServiceFixture()
        let quote = service.result()
        XCTAssertNoThrow(try quote.validate(owner: service.wallet.address, network: .arbitrum))
        XCTAssertThrowsError(try quote.validate(owner: "0x" + String(repeating: "3", count: 40), network: .arbitrum))
        XCTAssertThrowsError(try quote.validate(owner: service.wallet.address, network: .base))
        XCTAssertThrowsError(try quote.validate(owner: service.wallet.address, network: .monad))
        XCTAssertThrowsError(try quote.validate(owner: service.wallet.address, network: .ethereum))
        XCTAssertThrowsError(try quote.validate(owner: service.wallet.address, network: .bnb))
        let singleUse = ManagedFundingAddress(network: .arbitrum, recipient: service.wallet.address,
            refundAddress: service.wallet.address, depositAddress: quote.depositAddress,
            reusable: false, createdAt: Date())
        XCTAssertThrowsError(try singleUse.validate(owner: service.wallet.address, network: .arbitrum))
        XCTAssertNoThrow(try quote.validate(owner: service.wallet.address, network: .arbitrum,
                                            now: quote.createdAt.addingTimeInterval(61)))
        XCTAssertNoThrow(try quote.validate(owner: service.wallet.address, network: .arbitrum,
                                            now: quote.createdAt.addingTimeInterval(60 * 60 * 24)))
        XCTAssertThrowsError(try quote.validate(owner: service.wallet.address, network: .arbitrum,
                                               now: quote.createdAt.addingTimeInterval(-31)))
    }

    func testChangingInputClearsThePreviousQRCode() async {
        let service = FundingServiceFixture(), store: ManagedFundingStore
        store = ManagedFundingStore(service: service)
        await store.load(wallet: service.wallet)
        await store.prepare(wallet: service.wallet, network: .arbitrum)
        XCTAssertNotNil(store.address)
        store.invalidateAddress()
        XCTAssertNil(store.address)
        XCTAssertTrue(store.available)
        await store.prepare(wallet: service.wallet, network: .base)
        XCTAssertEqual(store.address?.network, .base)
        store.invalidateAddress()
        XCTAssertNil(store.address)
        await store.prepare(wallet: service.wallet, network: .monad)
        XCTAssertEqual(store.address?.network, .monad)
        XCTAssertNoThrow(try store.address?.validate(owner: service.wallet.address, network: .monad))
        store.invalidateAddress()
        await store.prepare(wallet: service.wallet, network: .ethereum)
        XCTAssertEqual(store.address?.network, .ethereum)
        store.invalidateAddress()
        await store.prepare(wallet: service.wallet, network: .bnb)
        XCTAssertEqual(store.address?.network, .bnb)
    }

    func testAccountSwitchAndClearDiscardLateAddress() async {
        for changeAccount in [true, false] {
            let service = FundingServiceFixture()
            let store = ManagedFundingStore(service: service)
            await store.load(wallet: service.wallet)
            service.beforeReturn = {
                if changeAccount { service.accountID = UUID() } else { store.clear() }
            }
            await store.prepare(wallet: service.wallet, network: .arbitrum)
            XCTAssertNil(store.address)
        }
    }

    func testHistoryFailuresPreserveRecordsAndDoNotBecomeEmptySuccess() async {
        let service = FundingServiceFixture()
        let store = ManagedFundingStore(service: service)
        await store.refreshHistory(wallet: service.wallet)
        XCTAssertEqual(store.deposits.count, 1)
        service.failHistory = true
        await store.refreshHistory(wallet: service.wallet)
        XCTAssertEqual(store.deposits.count, 1)
        XCTAssertNotNil(store.historyError)
        store.clear()
        XCTAssertTrue(store.deposits.isEmpty)
    }

    func testStatusDoesNotTurnRefundFailureOrUnknownIntoSuccess() {
        for status in ["refund", "failure", "unknown", "new-provider-state"] {
            let deposit = ManagedFundingDeposit(id: "id", status: status, createdAt: Date(), amount: nil)
            XCTAssertNotEqual(deposit.title, "Delivered to trading account")
        }
    }
}

@MainActor
private final class FundingServiceFixture: ManagedFundingServicing {
    let wallet = DeviceWalletSummary(accountID: UUID(), address: "0x" + String(repeating: "1", count: 40),
                                     recoveryVerified: true, provider: .privy)
    var accountID: UUID?
    var enabled = true
    var addressCount = 0
    var failHistory = false
    var beforeReturn: (() -> Void)?
    var beforeAvailabilityReturn: (() -> Void)?
    init() { accountID = wallet.accountID }
    func result(network: ManagedFundingNetwork = .arbitrum) -> ManagedFundingAddress {
        .init(network: network, recipient: wallet.address, refundAddress: wallet.address,
              depositAddress: "0x" + String(repeating: "2", count: 40), reusable: true, createdAt: Date())
    }
    func available(wallet: DeviceWalletSummary) async throws -> Bool {
        beforeAvailabilityReturn?(); return enabled
    }
    func address(wallet: DeviceWalletSummary, network: ManagedFundingNetwork) async throws -> ManagedFundingAddress {
        addressCount += 1; beforeReturn?(); return result(network: network)
    }
    func deposits(wallet: DeviceWalletSummary) async throws -> [ManagedFundingDeposit] {
        if failHistory { throw ManagedFundingError.unavailable }
        return [.init(id: "record", status: "pending", createdAt: Date(), amount: nil)]
    }
}
