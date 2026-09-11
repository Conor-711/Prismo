import XCTest
import WalletCore
@testable import BSmart

@MainActor
final class UnifiedAccountSetupTests: XCTestCase {
    func testIndependentViemDigestAndSignatureMatchAndCannotChangeOwner() throws {
        let wallet = BasicWalletTestService().wallet
        let setup = UnifiedAccountSetup(id: UUID(), accountID: wallet.accountID, owner: wallet.address,
            nonce: 1_789_084_800_001, createdAt: Date(timeIntervalSince1970: 1_789_084_800.001))
        let signature = "0x4e1317dc92b216aa2beb22d09c62cf2553261596457cad8feb567df8c7acdcf21bbcc601a03e1afab8a667397752f7d9c0f52e2dfc5dd9a45bc7adf0348f721a1c"
        XCTAssertEqual(FundingHex.encode(EthereumAbi.encodeTyped(messageJson: try UnifiedAccountSetupCodec.typedJSON(setup))),
                       "0x7d9f3812ff91ba4f41ac9e7e6d27542893fdf7e0df620f6d35df2045fd922375")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: UnifiedAccountSetupCodec.envelope(setup, signature: signature)) as? [String: Any])
        let action = try XCTUnwrap(body["action"] as? [String: Any])
        XCTAssertEqual(action["abstraction"] as? String, "unifiedAccount")
        XCTAssertEqual(action["user"] as? String, wallet.address)
        XCTAssertEqual(action["type"] as? String, "userSetAbstraction")
        XCTAssertNil(action["amount"]); XCTAssertNil(action["builder"])
        XCTAssertEqual(Set(body.keys), ["action", "signature", "nonce"])
        let other = UnifiedAccountSetup(id: UUID(), accountID: wallet.accountID, owner: "0x" + String(repeating: "1", count: 40),
            nonce: setup.nonce, createdAt: setup.createdAt)
        XCTAssertThrowsError(try UnifiedAccountSetupCodec.envelope(other, signature: signature))
        XCTAssertThrowsError(try setup.validate(wallet: wallet, now: setup.createdAt.addingTimeInterval(60)))
    }

    func testRefreshNeverSignsAndConfirmedModeRequiresReadBack() async throws {
        let f = SetupTestContext(); defer { f.cleanup() }
        let store = try f.store()
        await store.refresh(wallet: f.service.wallet)
        XCTAssertEqual(store.mode, .default)
        XCTAssertEqual(f.signer.count, 0)
        await store.enable(wallet: f.service.wallet)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.mode, .unifiedAccount)
        XCTAssertEqual(f.sender.count, 1)
        await store.enable(wallet: f.service.wallet)
        XCTAssertEqual(f.sender.count, 1)
    }

    func testUnbackedWalletSetupUsesActualLeaseRatherThanSynthesizedBackupState() async throws {
        let f = SetupTestContext(); defer { f.cleanup() }
        let wallet = DeviceWalletSummary(accountID: f.service.wallet.accountID, address: f.service.wallet.address, recoveryVerified: false)
        let store = try f.store()
        await store.enable(wallet: wallet)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.mode, .unifiedAccount)
        XCTAssertEqual(f.sender.count, 1)
        XCTAssertFalse(wallet.recoveryVerified)
    }

    func testPendingResponseWithoutModeChangeIsNotClaimedAsSuccessOrRetried() async throws {
        let f = SetupTestContext(); defer { f.cleanup() }
        f.sender.apply = false
        let store = try f.store()
        await store.enable(wallet: f.service.wallet)
        XCTAssertNotEqual(store.mode, .unifiedAccount)
        XCTAssertNotNil(store.errorMessage)
        await store.refresh(wallet: f.service.wallet)
        XCTAssertEqual(f.sender.count, 1)
    }

    func testDisabledNonFlatOrChangedAccountNeverSubmits() async throws {
        let f = SetupTestContext(); defer { f.cleanup() }
        let disabled = try f.store(enabled: false)
        await disabled.enable(wallet: f.service.wallet)
        XCTAssertEqual(f.signer.count, 0)
        f.reader.rows = ["xyz": [f.reader.position()]]
        let occupied = try f.store()
        await occupied.enable(wallet: f.service.wallet)
        XCTAssertEqual(f.signer.count, 0)
        f.reader.rows = [:]
        let changed = try f.store()
        f.signer.afterSigning = { f.service.walletAccountID = UUID() }
        await changed.enable(wallet: f.service.wallet)
        XCTAssertEqual(f.sender.count, 0)
    }

    func testSetupNoncePersistsAcrossJournalInstancesAndAdvancesOrderNonce() async throws {
        let f = SetupTestContext(); defer { f.cleanup() }
        let first = try await f.journal().reserveUnifiedAccountSetup(wallet: f.service.wallet)
        let second = try await f.journal().reserveUnifiedAccountSetup(wallet: f.service.wallet)
        XCTAssertGreaterThan(second.setup.nonce, first.setup.nonce)
        let orderNonce = try await f.journal().nextHyperliquidNonce(wallet: f.service.wallet)
        XCTAssertGreaterThan(orderNonce, second.setup.nonce)
        try second.consumeSigning(wallet: f.service.wallet, now: Date())
        XCTAssertThrowsError(try second.consumeSigning(wallet: f.service.wallet, now: Date()))
        XCTAssertThrowsError(try first.consumeSigning(wallet: .init(accountID: UUID(), address: f.service.wallet.address, recoveryVerified: true), now: Date()))
    }
}

@MainActor
private struct SetupTestContext {
    let base = OrderLifecycleContext()
    let service = BasicWalletTestService()
    let reader = BasicWalletTestReader()
    let signer = SetupTestSigner()
    let sender: SetupTestSender
    init() { sender = SetupTestSender(reader: reader) }
    func journal() throws -> FundingTransactionJournal {
        try .init(directory: base.directory, service: "setup-tests", keychain: base.keychain)
    }
    func cleanup() { base.cleanup() }
    func store(enabled: Bool = true) throws -> UnifiedAccountSetupStore {
        try .init(service: service, journal: journal(), reader: reader, signer: signer, sender: sender, enabled: { enabled })
    }
}

@MainActor
private final class SetupTestSigner: UnifiedAccountSetupSigning {
    var count = 0
    var afterSigning: (() -> Void)?
    func signUnifiedAccount(_ permit: UnifiedAccountSetupPermit, lease: FundingSigningLease) throws -> String {
        try permit.consumeSigning(wallet: lease.wallet, now: Date())
        let key = try XCTUnwrap(PrivateKey(data: Data(repeating: 0, count: 31) + Data([1])))
        let value = try lease.perform(wallet: lease.wallet) {
            EthereumMessageSigner.signTypedMessage(privateKey: key, messageJson: try UnifiedAccountSetupCodec.typedJSON(permit.setup))
        }
        count += 1; afterSigning?()
        return value.hasPrefix("0x") ? value : "0x" + value
    }
}

@MainActor
private final class SetupTestSender: UnifiedAccountSetupBroadcasting {
    let reader: BasicWalletTestReader
    var count = 0
    var apply = true
    init(reader: BasicWalletTestReader) { self.reader = reader }
    func submit(_ permit: UnifiedAccountSetupPermit, signature: String, lease: FundingSigningLease) throws -> Data? {
        _ = try permit.start(signature: signature, lease: lease) { $0 }
        XCTAssertThrowsError(try permit.start(signature: signature, lease: lease) { $0 })
        count += 1
        if apply { reader.mode = "unifiedAccount" }
        return nil
    }
}
