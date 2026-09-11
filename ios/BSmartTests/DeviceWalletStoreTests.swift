import XCTest
@testable import BSmart

@MainActor
final class DeviceWalletStoreTests: XCTestCase {
    func testOnlyVerifiedUnboundAccountCreatesAndBindsOnce() async {
        let service = WalletServiceDouble()
        let vault = WalletVaultDouble()
        let store = DeviceWalletStore(service: service, vault: vault)
        await store.prepare()
        XCTAssertEqual(store.state, .verified(.init(accountID: service.accountID, address: walletTestAddress, recoveryVerified: false)))
        XCTAssertEqual(service.bindCount, 1)
        store.lock()
        await store.prepare()
        let creates = await vault.creates
        XCTAssertEqual(creates, 1)
        XCTAssertEqual(service.bindCount, 1)
    }

    func testNetworkFailureNeverMeansNoWallet() async {
        let service = WalletServiceDouble()
        service.failRead = true
        let vault = WalletVaultDouble()
        let store = DeviceWalletStore(service: service, vault: vault)
        await store.prepare()
        let creates = await vault.creates
        XCTAssertEqual(creates, 0)
        XCTAssertEqual(store.state, .locked)
        XCTAssertNotNil(store.errorMessage)
    }

    func testRegisteredAddressMissingLocallyRequiresRecovery() async {
        let service = WalletServiceDouble()
        service.address = walletTestAddress
        let vault = WalletVaultDouble()
        let store = DeviceWalletStore(service: service, vault: vault)
        await store.prepare()
        XCTAssertEqual(store.state, .recoveryRequired(address: walletTestAddress))
        let creates = await vault.creates
        XCTAssertEqual(creates, 0)
    }

    func testLostBindingResponseReconcilesOriginalWalletInsteadOfCreatingAnother() async {
        let service = WalletServiceDouble()
        service.dropBindingResponse = true
        let vault = WalletVaultDouble()
        let store = DeviceWalletStore(service: service, vault: vault)
        await store.prepare()
        XCTAssertEqual(store.state, .locked)
        XCTAssertEqual(service.address, walletTestAddress)
        await store.prepare()
        XCTAssertEqual(store.state, .verified(.init(accountID: service.accountID, address: walletTestAddress, recoveryVerified: false)))
        let creates = await vault.creates
        XCTAssertEqual(creates, 1)
        XCTAssertEqual(service.bindCount, 1)
    }

    func testAccountSwitchDuringRequestCannotCreateWallet() async {
        let service = WalletServiceDouble()
        service.onRead = { service.walletAccountID = UUID() }
        let vault = WalletVaultDouble()
        let store = DeviceWalletStore(service: service, vault: vault)
        await store.prepare()
        let creates = await vault.creates
        XCTAssertEqual(creates, 0)
        XCTAssertEqual(store.state, .locked)
    }

    func testBackgroundLockInvalidatesInFlightRequest() async {
        let service = WalletServiceDouble()
        let vault = WalletVaultDouble()
        let store = DeviceWalletStore(service: service, vault: vault)
        service.onRead = { store.lock() }
        await store.prepare()
        let creates = await vault.creates
        XCTAssertEqual(creates, 0)
        XCTAssertEqual(store.state, .locked)
        XCTAssertNil(store.errorMessage)
    }

    func testWrongBackupCannotMarkRecoveryVerified() async {
        let service = WalletServiceDouble()
        let store = DeviceWalletStore(service: service, vault: WalletVaultDouble())
        await store.prepare()
        let incorrect = await store.confirmRecovery(phrase: "incorrect")
        XCTAssertFalse(incorrect)
        XCTAssertEqual(store.state, .verified(.init(accountID: service.accountID, address: walletTestAddress, recoveryVerified: false)))
        let correct = await store.confirmRecovery(phrase: walletTestPhrase)
        XCTAssertTrue(correct)
        XCTAssertEqual(store.state, .verified(.init(accountID: service.accountID, address: walletTestAddress, recoveryVerified: true)))
    }

    func testRestorationChecksOriginalAddressAndDoesNotUseCreation() async {
        let service = WalletServiceDouble()
        service.address = walletTestAddress
        let vault = WalletVaultDouble()
        let store = DeviceWalletStore(service: service, vault: vault)
        await store.prepare()
        let invalid = await store.restore(phrase: "incorrect")
        XCTAssertFalse(invalid)
        XCTAssertEqual(store.state, .recoveryRequired(address: walletTestAddress))
        let restored = await store.restore(phrase: walletTestPhrase)
        XCTAssertTrue(restored)
        let creates = await vault.creates
        XCTAssertEqual(creates, 0)
        XCTAssertEqual(service.bindCount, 1)
        XCTAssertEqual(store.state, .verified(.init(accountID: service.accountID, address: walletTestAddress, recoveryVerified: true)))
    }

    func testSecureStorageErrorNeverBindsOrExposesWallet() async {
        let service = WalletServiceDouble()
        let vault = WalletVaultDouble(failCreate: true)
        let store = DeviceWalletStore(service: service, vault: vault)
        await store.prepare()
        XCTAssertEqual(store.state, .locked)
        XCTAssertEqual(service.bindCount, 0)
        XCTAssertNil(service.address)
    }

    func testLoggedOutCannotReadCreateOrRevealWallet() async {
        let service = WalletServiceDouble()
        service.walletAccountID = nil
        let vault = WalletVaultDouble()
        let store = DeviceWalletStore(service: service, vault: vault)
        await store.prepare()
        let creates = await vault.creates
        XCTAssertEqual(creates, 0)
        XCTAssertEqual(service.reads, 0)
        do { _ = try await store.revealRecovery(); XCTFail("Logged-out disclosure") }
        catch { XCTAssertEqual(store.state, .locked) }
    }
}

private let walletTestAddress = "0xf278cf59f82edcf871d630f28ecc8056f25c1cdb"
private let walletTestPhrase = (Array(repeating: "abandon", count: 23) + ["art"]).joined(separator: " ")

@MainActor
private final class WalletServiceDouble: AccountWalletServicing {
    let accountID = UUID()
    var walletAccountID: UUID?
    var address: String?
    var failRead = false
    var dropBindingResponse = false
    var bindCount = 0
    var reads = 0
    var onRead: (() -> Void)?
    init() { walletAccountID = accountID }
    func walletRegistration() async throws -> TradingWalletRegistration {
        reads += 1
        onRead?()
        if failRead { throw URLError(.notConnectedToInternet) }
        return .init(accountId: accountID, address: address)
    }
    func walletChallenge(address: String) async throws -> TradingWalletChallenge {
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        return .init(id: UUID(), accountId: accountID, address: address, nonce: String(repeating: "a", count: 64),
                     issuedAt: now, expiresAt: now.addingTimeInterval(300))
    }
    func bindWallet(challenge: TradingWalletChallenge, signature: String) async throws -> TradingWalletRegistration {
        bindCount += 1
        address = challenge.address
        if dropBindingResponse { throw URLError(.timedOut) }
        return .init(accountId: accountID, address: address)
    }
}

private actor WalletVaultDouble: DeviceWalletVault {
    private var values: [UUID: DeviceWalletSummary] = [:]
    private(set) var creates = 0
    let failCreate: Bool
    init(failCreate: Bool = false) { self.failCreate = failCreate }
    func summary(accountID: UUID, registeredAddress: String?) -> DeviceWalletSummary? { values[accountID] }
    func create(accountID: UUID) throws -> DeviceWalletSummary {
        creates += 1
        if failCreate { throw DeviceWalletError.storage }
        guard values[accountID] == nil else { throw DeviceWalletError.alreadyExists }
        let value = DeviceWalletSummary(accountID: accountID, address: walletTestAddress, recoveryVerified: false)
        values[accountID] = value
        return value
    }
    func recoveryWords(accountID: UUID, address: String) throws -> [String] {
        guard values[accountID]?.address == address else { throw DeviceWalletError.recoveryRequired }
        return walletTestPhrase.split(separator: " ").map(String.init)
    }
    func verifyRecovery(accountID: UUID, address: String, phrase: String) throws -> DeviceWalletSummary {
        guard values[accountID]?.address == address else { throw DeviceWalletError.recoveryRequired }
        return try restore(accountID: accountID, address: address, phrase: phrase)
    }
    func restore(accountID: UUID, address: String, phrase: String) throws -> DeviceWalletSummary {
        guard phrase == walletTestPhrase, address == walletTestAddress else { throw DeviceWalletError.wrongRecovery }
        let value = DeviceWalletSummary(accountID: accountID, address: address, recoveryVerified: true)
        values[accountID] = value
        return value
    }
    func signBinding(accountID: UUID, challenge: TradingWalletChallenge) throws -> String {
        guard values[accountID]?.address == challenge.address else { throw DeviceWalletError.invalidProof }
        return "test-proof"
    }
}
