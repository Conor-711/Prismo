import XCTest
@testable import BSmart

final class HyperliquidDeviceSignerTests: XCTestCase {
    func testPublishedMnemonicVectorSignsOnlyMatchingOwnerAndBoundedOrder() throws {
        let entropy = Data(count: 32)
        let wallet = DeviceWalletSummary(accountID: UUID(), address: try DeviceWalletCryptography.address(entropy: entropy), recoveryVerified: true)
        let order = try makeOrder(wallet: wallet)
        let signature = try HyperliquidDeviceCryptography.sign(order: order, entropy: entropy, wallet: wallet, now: HyperliquidTradingFixture.now)
        XCTAssertNoThrow(try HyperliquidOrderCodec.envelope(order, signature: signature))
        XCTAssertThrowsError(try HyperliquidDeviceCryptography.sign(order: order, entropy: Data(repeating: 1, count: 32),
            wallet: wallet, now: HyperliquidTradingFixture.now))
        XCTAssertThrowsError(try HyperliquidDeviceCryptography.sign(order: order, entropy: entropy, wallet: wallet,
            now: Date(timeIntervalSince1970: Double(order.expiresAfter) / 1000)))
    }

    func testUnbackedVaultStillRequiresJournalPermitAndUserPresence() async throws {
        let fixture = try await fixture(recoveryVerified: false); defer { fixture.context.cleanup() }
        let signature = try await fixture.vault.signOrder(fixture.permit, lease: fixture.lease)
        XCTAssertNoThrow(try HyperliquidOrderCodec.envelope(fixture.permit.preview.order, signature: signature))
        XCTAssertTrue(fixture.keychain.authenticated)
        XCTAssertEqual(fixture.keychain.reads, 1)
        XCTAssertFalse(try JSONDecoder().decode(DeviceWalletRecord.self, from: fixture.keychain.bytes).recoveryVerified)
        await expectJournalFailure { try await fixture.vault.signOrder(fixture.permit, lease: fixture.lease) }
        XCTAssertEqual(fixture.keychain.reads, 1)
    }

    func testRevocationDuringProtectedReadPreventsSignature() async throws {
        let fixture = try await fixture(); defer { fixture.context.cleanup() }
        fixture.keychain.onRead = { fixture.lease.invalidate() }
        await expectJournalFailure { try await fixture.vault.signOrder(fixture.permit, lease: fixture.lease) }
    }

    private func makeOrder(wallet: DeviceWalletSummary) throws -> HyperliquidOrderIntent {
        try .init(wallet: wallet, market: HyperliquidQuoteFixture.market(), side: .buy, size: "0.1", limitPrice: "221",
            reduceOnly: false, cloid: "0x00000000000000000000000000000001", nonce: 1_789_084_801_000,
            expiresAfter: 1_789_084_861_000)
    }

    private func fixture(recoveryVerified: Bool = true) async throws -> (context: OrderLifecycleContext, keychain: FundingSignerKeychain,
        vault: KeychainDeviceWalletVault, permit: HyperliquidOrderSigningPermit, lease: FundingSigningLease) {
        let context = OrderLifecycleContext(), entropy = Data(count: 32)
        context.clock.advance(steady: context.clock.instant.duration(to: .now))
        let wallet = DeviceWalletSummary(accountID: UUID(), address: try DeviceWalletCryptography.address(entropy: entropy), recoveryVerified: recoveryVerified)
        let base = try HyperliquidQuoteFixture.snapshot(clock: context.clock)
        let snapshot = HyperliquidTradingSnapshot(accountID: wallet.accountID, owner: wallet.address, market: base.market,
            mode: base.mode, active: base.active, positions: base.positions, requestedAt: base.requestedAt,
            checkedAt: base.checkedAt, requestedContinuousAt: base.requestedContinuousAt, checkedContinuousAt: base.checkedContinuousAt)
        let reader = TradingCheckReaderStub(try [HyperliquidQuoteFixture.fees(), HyperliquidQuoteFixture.book()])
        let preview = try await HyperliquidOrderPreviewProvider(reader: reader, clock: { context.clock.now },
            continuousClock: { context.clock.instant }).preview(order: makeOrder(wallet: wallet), wallet: wallet,
                account: snapshot, reviewedLeverage: 10, reviewedMarginMode: .cross)
        let journal = try context.journal(), id = UUID()
        _ = try await journal.reserveOrder(id: id, preview: preview, wallet: wallet, continuousNow: context.clock.instant)
        let permit = try await journal.beginOrderSigning(id: id, preview: preview, wallet: wallet, continuousNow: context.clock.instant)
        let keychain = FundingSignerKeychain(bytes: try JSONEncoder().encode(DeviceWalletRecord(version: 1,
            accountID: wallet.accountID, address: wallet.address, entropy: entropy, recoveryVerified: recoveryVerified)))
        let vault = KeychainDeviceWalletVault(keychain: keychain, clock: { context.clock.now })
        let lease = FundingSigningLease(wallet: wallet, clock: { context.clock.now })
        return (context, keychain, vault, permit, lease)
    }
}
