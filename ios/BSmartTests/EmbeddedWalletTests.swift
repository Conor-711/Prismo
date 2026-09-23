import XCTest
import Security
import WalletCore
@testable import BSmart

@MainActor
final class EmbeddedWalletTests: XCTestCase {
    func testNewAccountCreatesAndBindsOnceWithoutLocalKeyOrMnemonic() async throws {
        let f = try EmbeddedWalletFixture(); defer { f.base.context.cleanup() }
        await f.store.prepare()
        XCTAssertEqual(f.store.state, .verified(f.wallet))
        XCTAssertEqual(f.remote.creates, 1)
        XCTAssertEqual(f.service.binds, 1)
        XCTAssertFalse(f.store.userPresenceRequired)
        XCTAssertFalse(f.wallet.recoveryVerified)
        f.store.lock()
        await f.store.prepare()
        XCTAssertEqual(f.store.state, .verified(f.wallet))
        XCTAssertEqual(f.remote.creates, 1)
        XCTAssertEqual(f.service.binds, 1)
        await expectJournalFailure { try await f.store.revealRecovery() }
    }

    func testRegisteredPrivyWalletRestoresOnEmptyDeviceWithoutCreating() async throws {
        let f = try EmbeddedWalletFixture(); defer { f.base.context.cleanup() }
        f.service.address = f.wallet.address; f.remote.exists = true
        await f.store.prepare()
        XCTAssertEqual(f.store.state, .verified(f.wallet))
        XCTAssertEqual(f.remote.creates, 0)
        XCTAssertEqual(f.service.binds, 0)
    }

    func testTradeWalletRetriesTransientSameSessionAccountCheckOnce() async throws {
        let f = try EmbeddedWalletFixture(); defer { f.base.context.cleanup() }
        f.service.address = f.wallet.address
        f.service.registrationFailures = 1
        f.remote.exists = true
        await f.store.prepare(allowCreation: false)
        XCTAssertEqual(f.store.state, .verified(f.wallet))
        XCTAssertNil(f.store.errorMessage)
        XCTAssertEqual(f.service.registrationCalls, 2)
        XCTAssertEqual(f.remote.creates, 0)
    }

    func testTradeWalletDoesNotRetryAfterSessionRevisionChanges() async throws {
        let f = try EmbeddedWalletFixture(); defer { f.base.context.cleanup() }
        f.service.address = f.wallet.address
        f.remote.exists = true
        f.remote.onResolve = { f.service.walletSessionRevision = UUID() }
        await f.store.prepare(allowCreation: false)
        XCTAssertEqual(f.store.state, .locked)
        XCTAssertEqual(f.remote.resolves, 1)
        XCTAssertNotNil(f.store.errorMessage)
    }

    func testExistingDeviceWalletDoesNotContactPrivyOrChangeAddress() async throws {
        let f = try EmbeddedWalletFixture(); defer { f.base.context.cleanup() }
        f.base.keychain.status = errSecSuccess
        f.service.address = f.wallet.address
        f.remote.error = EmbeddedWalletError.unavailable
        await f.store.prepare()
        XCTAssertEqual(f.store.state, .verified(f.base.wallet))
        XCTAssertTrue(f.store.userPresenceRequired)
        XCTAssertEqual(f.remote.resolves, 0)
    }

    func testUnknownRegisteredAddressNeverCreatesReplacement() async throws {
        let f = try EmbeddedWalletFixture(); defer { f.base.context.cleanup() }
        f.service.address = f.wallet.address
        await f.store.prepare()
        XCTAssertEqual(f.store.state, .recoveryRequired(address: f.wallet.address))
        XCTAssertEqual(f.remote.creates, 0)
        XCTAssertEqual(f.service.binds, 0)
    }

    func testProviderFailureNeverFallsBackToLocalCreation() async throws {
        for error in [EmbeddedWalletError.notConfigured, .unavailable, .identityMismatch] {
            let f = try EmbeddedWalletFixture(); defer { f.base.context.cleanup() }
            f.remote.error = error
            await f.store.prepare()
            XCTAssertEqual(f.store.state, .locked)
            XCTAssertNotNil(f.store.errorMessage)
            XCTAssertEqual(f.remote.creates, 0)
            XCTAssertEqual(f.service.binds, 0)
            XCTAssertEqual(f.base.keychain.status, errSecItemNotFound)
        }
    }

    func testLostBindingReplyRecoversSameProviderWallet() async throws {
        let f = try EmbeddedWalletFixture(); defer { f.base.context.cleanup() }
        f.service.dropReply = true
        await f.store.prepare()
        XCTAssertEqual(f.store.state, .locked)
        await f.store.prepare()
        XCTAssertEqual(f.store.state, .verified(f.wallet))
        XCTAssertEqual(f.remote.creates, 1)
        XCTAssertEqual(f.service.binds, 1)
    }

    func testAccountChangeAndBackgroundDuringResolveCannotBindOrPublish() async throws {
        for background in [false, true] {
            let f = try EmbeddedWalletFixture(); defer { f.base.context.cleanup() }
            f.remote.onResolve = {
                if background { f.store.lock() } else { f.service.walletAccountID = nil }
            }
            await f.store.prepare()
            XCTAssertEqual(f.store.state, .locked)
            XCTAssertEqual(f.remote.creates, 0)
            XCTAssertEqual(f.service.binds, 0)
        }
    }

    func testMismatchedProviderIdentityAndAddressRejectedBeforeBinding() async throws {
        for change in ["account", "address", "provider", "backup"] {
            let f = try EmbeddedWalletFixture(); defer { f.base.context.cleanup() }
            f.remote.exists = true
            f.service.address = f.wallet.address
            let value = DeviceWalletSummary(accountID: change == "account" ? UUID() : f.wallet.accountID,
                address: change == "address" ? "0x" + String(repeating: "1", count: 40) : f.wallet.address,
                recoveryVerified: change == "backup", provider: change == "provider" ? .device : .privy)
            f.remote.resultOverride = value
            await f.store.prepare()
            XCTAssertEqual(f.store.state, .locked)
            XCTAssertEqual(f.service.binds, 0)
        }
    }

    func testPersonalSignatureChecksOwnerAndUTF8MessageAndNormalizesV() throws {
        let remote = try EmbeddedWalletDouble(accountID: UUID())
        let text = "bSmart \u{4F60}\u{597D}"
        let raw = remote.personal(text)
        let bytes = try XCTUnwrap(FundingHex.decode(raw))
        let parity = FundingHex.encode(bytes.dropLast() + Data([bytes.last! - 27]))
        XCTAssertEqual(try EmbeddedWalletSignature.binding(parity, message: text, owner: remote.wallet.address), raw)
        XCTAssertThrowsError(try EmbeddedWalletSignature.binding(raw, message: text + "x", owner: remote.wallet.address))
        XCTAssertThrowsError(try EmbeddedWalletSignature.binding(raw, message: text, owner: "0x" + String(repeating: "1", count: 40)))
        XCTAssertThrowsError(try EmbeddedWalletSignature.parse("0x00"))
        XCTAssertThrowsError(try EmbeddedWalletSignature.parse(FundingHex.encode(bytes.dropLast() + Data([35]))))
    }

    func testPublicConfigurationRejectsMissingValuesAndBuildPlaceholders() {
        XCTAssertNil(PrivyWalletConfiguration(appID: nil, clientID: "client-test"))
        XCTAssertNil(PrivyWalletConfiguration(appID: "$(BSMART_PRIVY_APP_ID)", clientID: "client-test"))
        XCTAssertNotNil(PrivyWalletConfiguration(appID: "cmtyhnhcb01190cl08a0cvk3x", clientID: "client-test"))
    }
}

@MainActor
struct EmbeddedWalletFixture {
    let base: FundingSignerFixture
    let remote: EmbeddedWalletDouble
    let service: EmbeddedRegistrationService
    let vault: HybridTradingWalletVault
    let store: DeviceWalletStore
    var wallet: DeviceWalletSummary { remote.wallet }
    init() throws {
        base = try FundingSignerFixture(recoveryVerified: false)
        base.keychain.status = errSecItemNotFound
        remote = try EmbeddedWalletDouble(accountID: base.wallet.accountID)
        service = EmbeddedRegistrationService(wallet: remote.wallet)
        vault = HybridTradingWalletVault(local: base.signer(), embedded: remote)
        store = DeviceWalletStore(service: service, vault: vault, signing: vault)
    }
}

@MainActor
final class EmbeddedWalletDouble: EmbeddedWalletClient {
    let key: PrivateKey
    let wallet: DeviceWalletSummary
    var isConfigured = true
    var exists = false
    var error: Error?
    var resultOverride: DeviceWalletSummary?
    var onResolve: (() -> Void)?
    var onSign: (() -> Void)?
    var resolves = 0, creates = 0, typedRequests = 0, digestRequests = 0
    init(accountID: UUID) throws {
        // Public zero-entropy test vector, never a user's key or live provider.
        let hd = try XCTUnwrap(HDWallet(entropy: Data(count: 32), passphrase: ""))
        key = try XCTUnwrap(hd.getKey(coin: .ethereum, derivationPath: DeviceWalletCryptography.derivationPath))
        wallet = .init(accountID: accountID, address: CoinType.ethereum.deriveAddress(privateKey: key).lowercased(),
            recoveryVerified: false, provider: .privy)
    }
    func resolve(accountID: UUID, address: String?, create: Bool) async throws -> DeviceWalletSummary? {
        resolves += 1; onResolve?()
        if let error { throw error }
        if create { creates += 1; exists = true }
        return exists ? resultOverride ?? wallet : nil
    }
    func personal(_ text: String) -> String {
        let value = EthereumMessageSigner.signMessage(privateKey: key, message: text)
        return value.hasPrefix("0x") ? value : "0x" + value
    }
    func personalSign(accountID: UUID, address: String, message: String) async throws -> String {
        onSign?(); return personal(message)
    }
    func signTypedData(accountID: UUID, address: String, json: String) async throws -> String {
        typedRequests += 1; onSign?()
        let value = EthereumMessageSigner.signTypedMessage(privateKey: key, messageJson: json)
        return value.hasPrefix("0x") ? value : "0x" + value
    }
    func signDigest(accountID: UUID, address: String, digest: Data) async throws -> String {
        digestRequests += 1; onSign?()
        return FundingHex.encode(try XCTUnwrap(key.sign(digest: digest, curve: .secp256k1)))
    }
}

@MainActor
final class EmbeddedRegistrationService: AccountWalletServicing {
    let wallet: DeviceWalletSummary
    var walletAccountID: UUID?
    var walletSessionRevision = UUID()
    var address: String?
    var binds = 0
    var dropReply = false
    var registrationFailures = 0
    var registrationCalls = 0
    init(wallet: DeviceWalletSummary) { self.wallet = wallet; walletAccountID = wallet.accountID }
    func walletRegistration() async throws -> TradingWalletRegistration {
        registrationCalls += 1
        if registrationFailures > 0 {
            registrationFailures -= 1
            throw DeviceWalletError.accountChanged
        }
        return .init(accountId: wallet.accountID, address: address)
    }
    func walletChallenge(address: String) async throws -> TradingWalletChallenge {
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        return .init(id: UUID(), accountId: wallet.accountID, address: address, nonce: String(repeating: "a", count: 64),
            issuedAt: now, expiresAt: now.addingTimeInterval(300))
    }
    func bindWallet(challenge: TradingWalletChallenge, signature: String) async throws -> TradingWalletRegistration {
        _ = try EmbeddedWalletSignature.binding(signature,
            message: challenge.message(accountID: wallet.accountID, address: wallet.address), owner: wallet.address)
        binds += 1; address = wallet.address
        if dropReply { throw URLError(.timedOut) }
        return .init(accountId: wallet.accountID, address: address)
    }
}
