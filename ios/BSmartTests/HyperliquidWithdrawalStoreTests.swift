import XCTest
import WalletCore
@testable import BSmart

@MainActor
final class HyperliquidWithdrawalStoreTests: XCTestCase {
    typealias F = HyperliquidTradingFixture

    func testDeviceCryptographyBindsWalletRecipientAndAmount() throws {
        let entropy = Data(repeating: 35, count: 32)
        let wallet = DeviceWalletSummary(accountID: UUID(), address: try DeviceWalletCryptography.address(entropy: entropy), recoveryVerified: true)
        let now = Date()
        let intent = try HyperliquidWithdrawalIntent(wallet: wallet, recipient: HyperliquidQuoteFixture.recipient,
            amount: "10", source: .perps, nonce: UInt64(now.timeIntervalSince1970 * 1000))
        let signature = try HyperliquidWithdrawalCryptography.sign(intent: intent, entropy: entropy, wallet: wallet, now: now)
        XCTAssertNoThrow(try HyperliquidWithdrawalCodec.envelope(intent, signature: signature))
        let changed = try HyperliquidWithdrawalIntent(wallet: wallet, recipient: intent.recipient, amount: "11", source: .perps, nonce: intent.nonce)
        XCTAssertThrowsError(try HyperliquidWithdrawalCodec.envelope(changed, signature: signature))
        XCTAssertThrowsError(try HyperliquidWithdrawalCryptography.sign(intent: intent, entropy: Data(repeating: 36, count: 32), wallet: wallet, now: now))
        XCTAssertThrowsError(try HyperliquidWithdrawalCryptography.sign(intent: intent, entropy: entropy, wallet: wallet, now: now.addingTimeInterval(60)))
    }

    func testReviewDoesNotSignAndConfirmationSendsOnlyOnce() async throws {
        let fixture = WithdrawalStoreFixture(); defer { fixture.base.cleanup() }
        let store = try fixture.store()
        await fixture.review(store)
        XCTAssertNotNil(store.preview)
        XCTAssertEqual(fixture.signer.count, 0)
        await store.confirm(wallet: F.wallet)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.result?.state, .accepted)
        await store.confirm(wallet: F.wallet)
        XCTAssertEqual(fixture.signer.count, 1)
        XCTAssertEqual(fixture.sender.count, 1)
        let body = try XCTUnwrap(fixture.sender.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let action = try XCTUnwrap(json["action"] as? [String: Any])
        XCTAssertEqual(action["type"] as? String, "sendToEvmWithData")
        XCTAssertEqual(action["sourceDex"] as? String, "")
        XCTAssertEqual(action["destinationChainId"] as? Int, 3)
        XCTAssertNil(action["builder"])
    }

    func testInternalUnbackedWalletCanReviewAndConfirmWithdrawalWithoutChangingBackupState() async throws {
        let fixture = WithdrawalStoreFixture(); defer { fixture.base.cleanup() }
        let store = try fixture.store()
        let wallet = DeviceWalletSummary(accountID: F.wallet.accountID, address: F.wallet.address, recoveryVerified: false)
        await store.review(amount: "10", recipient: HyperliquidQuoteFixture.recipient, wallet: wallet)
        XCTAssertNotNil(store.preview)
        XCTAssertEqual(fixture.signer.count, 0)
        await store.confirm(wallet: wallet)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.result?.state, .accepted)
        XCTAssertEqual(fixture.sender.count, 1)
        XCTAssertFalse(wallet.recoveryVerified)
    }

    func testDisabledFlowCannotReadSignOrSubmit() async throws {
        let fixture = WithdrawalStoreFixture(); defer { fixture.base.cleanup() }
        let store = try fixture.store(enabled: false)
        await fixture.review(store)
        await store.confirm(wallet: F.wallet)
        XCTAssertNil(store.preview)
        XCTAssertEqual(fixture.provider.reads, 0)
        XCTAssertEqual(fixture.signer.count, 0)
        XCTAssertEqual(fixture.sender.count, 0)
    }

    func testInsufficientBalanceAndSharedBalanceCannotSign() async throws {
        let fixture = WithdrawalStoreFixture(); defer { fixture.base.cleanup() }
        let store = try fixture.store()
        fixture.provider.available = "1"
        await fixture.review(store)
        XCTAssertNil(store.preview)
        fixture.provider.available = "100"
        fixture.provider.mode = .unifiedAccount
        await fixture.review(store)
        XCTAssertNil(store.preview)
        XCTAssertEqual(fixture.signer.count, 0)
    }

    func testChangedFeeRequiresAnotherReview() async throws {
        let fixture = WithdrawalStoreFixture(); defer { fixture.base.cleanup() }
        let store = try fixture.store()
        await fixture.review(store)
        fixture.provider.fee = 300_000
        await store.confirm(wallet: F.wallet)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(fixture.signer.count, 0)
        XCTAssertEqual(fixture.sender.count, 0)
    }

    func testFlatUnifiedAccountWithdrawsFromSpotAndRejectsHeldMargin() async throws {
        let fixture = WithdrawalStoreFixture(); defer { fixture.base.cleanup() }
        fixture.provider.mode = .unifiedAccount
        fixture.provider.flat = true
        let store = try fixture.store()
        await fixture.review(store)
        XCTAssertEqual(store.preview?.intent.source, .spot)
        XCTAssertEqual(store.preview?.available, "100")
        await store.confirm(wallet: F.wallet)
        XCTAssertEqual(store.result?.state, .accepted)
        XCTAssertEqual(store.result?.intent.source, "spot")
        let held = try fixture.store()
        fixture.provider.held = "1"
        await fixture.review(held)
        XCTAssertNil(held.preview)
        XCTAssertEqual(fixture.signer.count, 1)
    }

    func testSlowReviewGetsFreshNonceBeforeSigning() async throws {
        let fixture = WithdrawalStoreFixture(); defer { fixture.base.cleanup() }
        let store = try fixture.store()
        await fixture.review(store)
        let oldNonce = try XCTUnwrap(store.preview?.intent.nonce)
        fixture.base.clock.advance(wall: 5, steady: .seconds(5))
        await store.confirm(wallet: F.wallet)
        XCTAssertNil(store.errorMessage)
        XCTAssertGreaterThan(try XCTUnwrap(store.result?.intent.nonce), oldNonce)
        XCTAssertEqual(fixture.sender.count, 1)
    }

    func testUnknownResponseCannotBeResentAfterRestart() async throws {
        let fixture = WithdrawalStoreFixture(); defer { fixture.base.cleanup() }
        fixture.sender.response = nil
        let store = try fixture.store()
        await fixture.review(store)
        await store.confirm(wallet: F.wallet)
        XCTAssertEqual(store.result?.state, .uncertain)
        let resumed = try fixture.store()
        await fixture.review(resumed)
        await resumed.confirm(wallet: F.wallet)
        XCTAssertNil(resumed.preview)
        XCTAssertEqual(resumed.result?.state, .uncertain)
        XCTAssertEqual(fixture.sender.count, 1)
    }

    func testLeavingAfterSignatureKeepsEvidenceWithoutSending() async throws {
        let fixture = WithdrawalStoreFixture(); defer { fixture.base.cleanup() }
        let store = try fixture.store()
        await fixture.review(store)
        fixture.signer.afterSigning = { store.invalidate() }
        await store.confirm(wallet: F.wallet)
        let records = try await fixture.base.journal().withdrawalRecords(wallet: F.wallet)
        XCTAssertEqual(records.first?.state, .signed)
        XCTAssertNotNil(records.first?.signature)
        XCTAssertEqual(fixture.sender.count, 0)
    }

    func testInvalidAddressAndTooSmallAmountNeverSign() async throws {
        let fixture = WithdrawalStoreFixture(); defer { fixture.base.cleanup() }
        let store = try fixture.store()
        await store.review(amount: "10", recipient: "0x0000000000000000000000000000000000000000", wallet: F.wallet)
        XCTAssertNil(store.preview)
        await store.review(amount: "0.2", recipient: HyperliquidQuoteFixture.recipient, wallet: F.wallet)
        XCTAssertNil(store.preview)
        XCTAssertEqual(fixture.signer.count, 0)
    }
}

@MainActor
private struct WithdrawalStoreFixture {
    let base = OrderLifecycleContext()
    let provider: WithdrawalStoreProvider
    let signer: WithdrawalStoreSigner
    let sender = WithdrawalStoreSender()
    init() {
        provider = .init(clock: base.clock)
        signer = .init(clock: base.clock)
    }
    func store(enabled: Bool = true) throws -> HyperliquidWithdrawalStore {
        try .init(service: OrderStoreAccount(clock: base.clock), journal: base.journal(), provider: provider,
                  signer: signer, broadcaster: sender, clock: { base.clock.now },
                  continuousClock: { base.clock.instant }, enabled: { enabled })
    }
    func review(_ store: HyperliquidWithdrawalStore) async {
        await store.review(amount: "10", recipient: HyperliquidQuoteFixture.recipient, wallet: HyperliquidTradingFixture.wallet)
    }
}

@MainActor
private final class WithdrawalStoreProvider: HyperliquidWithdrawalPreparing {
    let clock: TradingCheckClock
    var mode = HyperCoreAccountMode.default
    var available = "100"
    var fee: UInt64 = 200_000
    var reads = 0
    var flat = false
    var held = "0"
    init(clock: TradingCheckClock) { self.clock = clock }
    func source(wallet: DeviceWalletSummary) throws -> HyperliquidWithdrawalIntent.Source {
        mode == .unifiedAccount ? .spot : .perps
    }
    func preview(intent: HyperliquidWithdrawalIntent, wallet: DeviceWalletSummary) throws -> HyperliquidWithdrawalPreview {
        reads += 1
        let now = clock.now, instant = clock.instant
        let balance = try HyperCoreBalanceSnapshot(accountID: wallet.accountID, owner: wallet.address, mode: mode,
            usdc: HyperCoreUSDCAmount("100"), held: HyperCoreUSDCAmount(held),
            perps: mode.usesSharedBalance ? nil : .init(equity: HyperCoreUSDCAmount("100"),
                withdrawable: HyperCoreUSDCAmount(available), updatedAt: now), requestedAt: now, checkedAt: now)
        let block = try FundingSourceBlock(.object(["number": .string("0x123"), "hash": .string("0x" + String(repeating: "a", count: 64)),
            "timestamp": .string(FundingQuantity(UInt64(now.timeIntervalSince1970)).rpc)]), now: now, fresh: true)
        let fee = CCTPWithdrawalFeeSnapshot(head: block, contractCodeHash: "0x" + String(repeating: "b", count: 64),
            maximumCCTPFee: FundingQuantity(fee), requestedAt: now, checkedAt: now,
            requestedContinuousAt: instant, checkedContinuousAt: instant)
        return .init(intent: intent, balance: balance, fee: fee,
                     flatAccount: flat ? .init(owner: wallet.address, checkedAt: now, startedAt: now) : nil)
    }
}

@MainActor
private final class WithdrawalStoreSigner: HyperliquidWithdrawalSigning {
    let clock: TradingCheckClock
    var count = 0
    var afterSigning: (() -> Void)?
    init(clock: TradingCheckClock) { self.clock = clock }
    func signWithdrawal(_ permit: HyperliquidWithdrawalSigningPermit, lease: FundingSigningLease) throws -> String {
        try permit.consume(wallet: lease.wallet, now: clock.now, continuousNow: clock.instant)
        let key = try XCTUnwrap(PrivateKey(data: Data(repeating: 0, count: 31) + Data([1])))
        let signature = try lease.perform(wallet: lease.wallet) {
            EthereumMessageSigner.signTypedMessage(privateKey: key, messageJson: try HyperliquidWithdrawalCodec.typedJSON(permit.preview.intent))
        }
        count += 1; afterSigning?()
        return signature.hasPrefix("0x") ? signature : "0x" + signature
    }
}

@MainActor
private final class WithdrawalStoreSender: HyperliquidWithdrawalBroadcasting {
    var count = 0
    var body: Data?
    var response: Data? = WithdrawalJournalContext.accepted
    func submit(_ permit: HyperliquidWithdrawalSubmissionPermit, lease: FundingSigningLease) throws -> Data? {
        body = try permit.start(lease: lease) { $0 }
        XCTAssertThrowsError(try permit.start(lease: lease) { $0 })
        count += 1
        return response
    }
}
