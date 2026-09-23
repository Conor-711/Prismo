import XCTest
@testable import BSmart

@MainActor
final class EmbeddedWalletSigningTests: XCTestCase {
    func testCCTPAuthorizationAndRawTransactionKeepJournalAndExactOwner() async throws {
        let base = try FundingSignerFixture(recoveryVerified: false); defer { base.context.cleanup() }
        let remote = try EmbeddedWalletDouble(accountID: base.wallet.accountID), wallet = remote.wallet
        let signer = HybridTradingWalletVault(local: base.signer(), embedded: remote, clock: { base.context.clock.now })
        let journal = try base.context.journal(), id = UUID()
        let lease = FundingSigningLease(wallet: wallet, clock: { base.context.clock.now })
        _ = try await journal.beginConsent(id: id, plan: base.plan, wallet: wallet)
        let authorizationPermit = try await journal.beginAuthorization(id: id, wallet: wallet)
        let authorization = try await signer.authorizeDeposit(authorizationPermit, lease: lease)
        _ = try await journal.recordAuthorization(id: id, signature: authorization, wallet: wallet)
        let tx = try await base.transaction(authorization: authorization)
        _ = try await journal.reserve(id: id, transaction: tx, wallet: wallet)
        let permit = try await journal.beginSigning(id: id, transaction: tx, wallet: wallet)
        let signature = try await signer.signDeposit(permit, transaction: tx, lease: lease)
        let saved = try await journal.recordSignature(id: id, signature: signature, wallet: wallet)
        XCTAssertEqual(saved.state, .signed)
        XCTAssertNotNil(saved.signed?.hash)
        XCTAssertEqual(remote.typedRequests, 1)
        XCTAssertEqual(remote.digestRequests, 1)
        XCTAssertEqual(base.keychain.reads, 0)
    }

    func testRevokedLeaseBeforeOrDuringRemoteSignatureCannotReturnAuthorization() async throws {
        for during in [false, true] {
            let base = try FundingSignerFixture(); defer { base.context.cleanup() }
            let remote = try EmbeddedWalletDouble(accountID: base.wallet.accountID)
            let signer = HybridTradingWalletVault(local: base.signer(), embedded: remote, clock: { base.context.clock.now })
            let permit = try await base.authorizationPermit()
            let lease = FundingSigningLease(wallet: remote.wallet, clock: { base.context.clock.now })
            if during { remote.onSign = { lease.invalidate() } } else { lease.invalidate() }
            await expectJournalFailure { try await signer.authorizeDeposit(permit, lease: lease) }
            XCTAssertEqual(remote.typedRequests, during ? 1 : 0)
            XCTAssertEqual(base.keychain.reads, 0)
        }
    }

    func testDeviceSigningContinuesToUseLocalVaultOnly() async throws {
        let base = try FundingSignerFixture(); defer { base.context.cleanup() }
        let remote = try EmbeddedWalletDouble(accountID: base.wallet.accountID)
        let signer = HybridTradingWalletVault(local: base.signer(), embedded: remote, clock: { base.context.clock.now })
        let permit = try await base.authorizationPermit()
        _ = try await signer.authorizeDeposit(permit, lease: FundingSigningLease(wallet: base.wallet))
        XCTAssertEqual(remote.typedRequests, 0)
        XCTAssertEqual(base.keychain.reads, 1)
    }

    func testUnifiedBalanceAndLeverageSignaturesAreVerifiableAndSingleUse() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let remote = try EmbeddedWalletDouble(accountID: UUID()), wallet = remote.wallet
        let signer = HybridTradingWalletVault(embedded: remote, clock: { context.clock.now })
        let journal = try context.journal(), lease = FundingSigningLease(wallet: wallet, clock: { context.clock.now })
        let setup = try await journal.reserveUnifiedAccountSetup(wallet: wallet)
        let signature = try await signer.signUnifiedAccount(setup, lease: lease)
        XCTAssertNoThrow(try UnifiedAccountSetupCodec.envelope(setup.setup, signature: signature))
        await expectJournalFailure { try await signer.signUnifiedAccount(setup, lease: lease) }
        let leverage = try await journal.reserveLeverage(wallet: wallet, market: HyperliquidQuoteFixture.market(), leverage: 5, isCross: true)
        let leverageSignature = try await signer.signLeverage(leverage, lease: lease)
        XCTAssertNoThrow(try HyperliquidLeverageCodec.envelope(leverage.update, signature: leverageSignature))
        await expectJournalFailure { try await signer.signLeverage(leverage, lease: lease) }
        XCTAssertEqual(remote.typedRequests, 2)
    }

    func testMarketOrderUsesEmbeddedSignerAndRejectsReuse() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        context.clock.advance(steady: context.clock.instant.duration(to: .now))
        let remote = try EmbeddedWalletDouble(accountID: UUID()), wallet = remote.wallet
        let signer = HybridTradingWalletVault(embedded: remote, clock: { context.clock.now })
        let base = try HyperliquidQuoteFixture.snapshot(clock: context.clock)
        let snapshot = HyperliquidTradingSnapshot(accountID: wallet.accountID, owner: wallet.address, market: base.market,
            mode: base.mode, active: base.active, positions: base.positions, requestedAt: base.requestedAt,
            checkedAt: base.checkedAt, requestedContinuousAt: base.requestedContinuousAt, checkedContinuousAt: base.checkedContinuousAt)
        let order = try HyperliquidOrderIntent(wallet: wallet, market: HyperliquidQuoteFixture.market(), side: .buy,
            size: "0.1", limitPrice: "221", reduceOnly: false, cloid: "0x00000000000000000000000000000001",
            nonce: UInt64(context.clock.now.timeIntervalSince1970 * 1000),
            expiresAfter: UInt64(context.clock.now.timeIntervalSince1970 * 1000) + 60_000)
        let reader = TradingCheckReaderStub(preview: try [HyperliquidQuoteFixture.fees(), HyperliquidQuoteFixture.book()])
        let preview = try await HyperliquidOrderPreviewProvider(reader: reader, clock: { context.clock.now },
            continuousClock: { context.clock.instant }).preview(order: order, wallet: wallet, account: snapshot,
                reviewedLeverage: 10, reviewedMarginMode: .cross)
        let journal = try context.journal(), id = UUID()
        _ = try await journal.reserveOrder(id: id, preview: preview, wallet: wallet, continuousNow: context.clock.instant)
        let permit = try await journal.beginOrderSigning(id: id, preview: preview, wallet: wallet, continuousNow: context.clock.instant)
        let lease = FundingSigningLease(wallet: wallet, clock: { context.clock.now })
        let signature = try await signer.signOrder(permit, lease: lease)
        XCTAssertNoThrow(try HyperliquidOrderCodec.envelope(order, signature: signature))
        await expectJournalFailure { try await signer.signOrder(permit, lease: lease) }
        XCTAssertEqual(remote.typedRequests, 1)
    }

    func testWithdrawalUsesSameSignerAndCannotBeSignedTwice() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        context.clock.advance(steady: context.clock.instant.duration(to: .now))
        let remote = try EmbeddedWalletDouble(accountID: UUID()), wallet = remote.wallet
        let signer = HybridTradingWalletVault(embedded: remote, clock: { context.clock.now })
        let now = context.clock.now, instant = context.clock.instant
        let intent = try HyperliquidWithdrawalIntent(wallet: wallet, recipient: "0x" + String(repeating: "2", count: 40),
            amount: "10", source: .perps, nonce: UInt64(now.timeIntervalSince1970 * 1000))
        let balance = try HyperCoreBalanceSnapshot(accountID: wallet.accountID, owner: wallet.address, mode: .default,
            usdc: HyperCoreUSDCAmount("0"), held: HyperCoreUSDCAmount("0"),
            perps: .init(equity: HyperCoreUSDCAmount("100"), withdrawable: HyperCoreUSDCAmount("100"), updatedAt: now),
            requestedAt: now, checkedAt: now)
        let block = try FundingSourceBlock(.object(["number": .string("0x123"), "hash": .string("0x" + String(repeating: "a", count: 64)),
            "timestamp": .string(FundingQuantity(UInt64(now.timeIntervalSince1970)).rpc)]), now: now, fresh: true)
        let fee = CCTPWithdrawalFeeSnapshot(head: block, contractCodeHash: "0x" + String(repeating: "b", count: 64),
            maximumCCTPFee: FundingQuantity(200_000), requestedAt: now, checkedAt: now,
            requestedContinuousAt: instant, checkedContinuousAt: instant)
        let preview = HyperliquidWithdrawalPreview(intent: intent, balance: balance, fee: fee)
        let journal = try context.journal(), id = UUID()
        _ = try await journal.reserveWithdrawal(id: id, intent: intent, wallet: wallet)
        let permit = try await journal.beginWithdrawalSigning(id: id, preview: preview, wallet: wallet, continuousNow: instant)
        let lease = FundingSigningLease(wallet: wallet, clock: { context.clock.now })
        let signature = try await signer.signWithdrawal(permit, lease: lease)
        XCTAssertNoThrow(try HyperliquidWithdrawalCodec.envelope(intent, signature: signature))
        await expectJournalFailure { try await signer.signWithdrawal(permit, lease: lease) }
        XCTAssertEqual(remote.typedRequests, 1)
    }
}
