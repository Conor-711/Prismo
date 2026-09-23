import XCTest
import WalletCore
@testable import BSmart

@MainActor
final class HyperliquidMarketOrderStoreTests: XCTestCase {
    typealias F = HyperliquidTradingFixture

    func testAttributionDelayRefreshesExactIntentOnceBeforeSigning() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let reader = OrderStoreReader(clock: context.clock)
        let signer = OrderStoreSigner(clock: context.clock), sender = OrderStoreSender()
        let attribution = OrderAttributionStub()
        attribution.onRegister = { context.clock.advance(wall: 6, steady: .seconds(6)) }
        let store = try make(context, reader: reader, signer: signer, sender: sender, attribution: attribution)
        await store.executeMargin("1.1", leverage: 10, side: .buy, wallet: F.wallet, dex: "xyz", coin: F.coin)
        XCTAssertNil(store.errorMessage)
        let registered = try XCTUnwrap(attribution.orders.first)
        XCTAssertEqual(attribution.orders.count, 1)
        XCTAssertEqual(store.result?.order.cloid, registered.cloid)
        XCTAssertEqual(store.result?.order.size, registered.size.wire)
        XCTAssertEqual(store.result?.order.limitPrice, registered.limitPrice.wire)
        XCTAssertEqual(signer.count, 1)
        let count = await sender.count; XCTAssertEqual(count, 1)
    }

    func testStaleReadOnlySnapshotRetriesBeforeOneSignatureAndOneSubmission() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let reader = OrderStoreReader(clock: context.clock)
        await reader.staleNextPosition()
        let signer = OrderStoreSigner(clock: context.clock), sender = OrderStoreSender()
        let store = try make(context, reader: reader, signer: signer, sender: sender)

        await store.executeMargin("1.1", leverage: 10, side: .buy, wallet: F.wallet, dex: "xyz", coin: F.coin)

        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(signer.count, 1)
        let submissions = await sender.count
        XCTAssertEqual(submissions, 1)
    }

    func testTransientReadFailureRetriesBeforeOneSignatureAndSubmission() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let reader = OrderStoreReader(clock: context.clock)
        await reader.failNextDexRead()
        let signer = OrderStoreSigner(clock: context.clock), sender = OrderStoreSender()
        let store = try make(context, reader: reader, signer: signer, sender: sender)

        await store.executeMargin("1.1", leverage: 10, side: .buy, wallet: F.wallet, dex: "xyz", coin: F.coin)

        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(signer.count, 1)
        let submissions = await sender.count
        XCTAssertEqual(submissions, 1)
    }

    func testSameAccountSessionRefreshDoesNotMasqueradeAsAccountSwitch() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let account = OrderStoreAccount(clock: context.clock)
        account.walletAccountID = nil
        account.walletSessionIsRefreshing = true
        let signer = OrderStoreSigner(clock: context.clock), sender = OrderStoreSender()
        let store = try make(context, service: account, reader: OrderStoreReader(), signer: signer, sender: sender)
        let order = Task {
            await store.executeMargin("1.1", leverage: 10, side: .buy, wallet: F.wallet, dex: "xyz", coin: F.coin)
        }
        try await Task.sleep(for: .milliseconds(150))
        account.walletAccountID = F.wallet.accountID
        account.walletSessionIsRefreshing = false
        await order.value

        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(signer.count, 1)
        let submissions = await sender.count
        XCTAssertEqual(submissions, 1)
    }

    func testRealAccountSwitchDuringRefreshNeverSignsOrSubmits() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let account = OrderStoreAccount(clock: context.clock)
        account.walletAccountID = nil
        account.walletSessionIsRefreshing = true
        let signer = OrderStoreSigner(clock: context.clock), sender = OrderStoreSender()
        let store = try make(context, service: account, reader: OrderStoreReader(), signer: signer, sender: sender)
        let order = Task {
            await store.executeMargin("1.1", leverage: 10, side: .buy, wallet: F.wallet, dex: "xyz", coin: F.coin)
        }
        try await Task.sleep(for: .milliseconds(150))
        account.walletSessionRevision = UUID()
        account.walletAccountID = UUID()
        account.walletSessionIsRefreshing = false
        await order.value

        XCTAssertEqual(store.errorMessage, DeviceWalletError.accountChanged.localizedDescription)
        XCTAssertEqual(signer.count, 0)
        let submissions = await sender.count
        XCTAssertEqual(submissions, 0)
    }

    func testSameAccountRegistryRefreshRetriesOnceBeforeSigning() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let account = OrderStoreAccount(clock: context.clock)
        account.expiredRegistrationOnce = true
        let signer = OrderStoreSigner(clock: context.clock), sender = OrderStoreSender()
        let store = try make(context, service: account, reader: OrderStoreReader(), signer: signer, sender: sender)

        await store.executeMargin("1.1", leverage: 10, side: .buy, wallet: F.wallet, dex: "xyz", coin: F.coin)

        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(account.registrationAttempts, 4)
        XCTAssertEqual(signer.count, 1)
        let submissions = await sender.count
        XCTAssertEqual(submissions, 1)
    }

    func testExpiredIntentOrChangedModeCannotBeRevivedAfterAttribution() async throws {
        for changeMode in [false, true] {
            let context = OrderLifecycleContext(); defer { context.cleanup() }
            let reader = OrderStoreReader(clock: context.clock)
            let signer = OrderStoreSigner(clock: context.clock), sender = OrderStoreSender()
            let attribution = OrderAttributionStub()
            attribution.afterRegister = {
                let delay: Double = changeMode ? 6 : 61
                context.clock.advance(wall: delay, steady: .seconds(delay))
                if changeMode { await reader.setMode("default") }
            }
            let store = try make(context, reader: reader, signer: signer, sender: sender, attribution: attribution)
            await store.executeMargin("1.1", leverage: 10, side: .buy, wallet: F.wallet, dex: "xyz", coin: F.coin)
            XCTAssertNotNil(store.errorMessage)
            XCTAssertNil(store.result)
            XCTAssertEqual(attribution.orders.count, 1)
            XCTAssertEqual(signer.count, 0)
            let count = await sender.count; XCTAssertEqual(count, 0)
        }
    }

    func testNetworkAndQuoteFailuresAreNotMisreportedAsAccountChanges() {
        for error: Error in [HyperliquidTradingCheckError.unavailable, HyperliquidTradingCheckError.stale,
                            HyperliquidTradingCheckError.leverageChanged, HyperliquidTradingCheckError.exceedsCapacity,
                            HyperliquidQuoteError.stale, HyperliquidQuoteError.feesUnavailable] {
            XCTAssertNotEqual(HyperliquidOrderFailure.message(error), HyperliquidLiveOrderError.changed.localizedDescription)
        }
        XCTAssertTrue(HyperliquidOrderFailure.isExpiredObservation(HyperliquidQuoteError.stale))
        XCTAssertFalse(HyperliquidOrderFailure.isExpiredObservation(HyperliquidTradingCheckError.leverageChanged))
        XCTAssertFalse(HyperliquidOrderFailure.isExpiredObservation(HyperliquidTradingCheckError.unavailable))
    }

    func testReductionAfterLegacyContainerLossKeepsOldAnchorAndSubmitsOnlyOnce() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let keychain = InstallationTestKeychain()
        let directory = context.directory.appendingPathComponent("ledger")
        let legacy = try FundingTransactionJournal(directory: directory, service: "order-installation", keychain: keychain,
            clock: { context.clock.now })
        _ = try await legacy.reserveOrder(id: UUID(), preview: context.preview(), wallet: F.wallet,
            continuousNow: context.clock.instant)
        let before = keychain.snapshot
        try FileManager.default.removeItem(at: context.directory)
        let journal = try FundingTransactionJournal(directory: directory, service: "order-installation", keychain: keychain,
            installationMarker: context.directory.appendingPathComponent("installation.json"), clock: { context.clock.now })
        let reader = OrderStoreReader(), signer = OrderStoreSigner(clock: context.clock), sender = OrderStoreSender()
        await reader.setPosition("0.018")
        let store = HyperliquidMarketOrderStore(service: OrderStoreAccount(clock: context.clock), journal: journal,
            reader: reader, signer: signer, broadcaster: sender, clock: { context.clock.now },
            continuousClock: { context.clock.instant }, enabled: { true })
        await store.reviewReduction(percent: 100, slippageBPS: 50, wallet: F.wallet, dex: "xyz", coin: F.coin)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.preview?.order.size.wire, "0.018")
        await store.confirm(wallet: F.wallet)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.result?.state, .filled)
        XCTAssertEqual(store.result?.order.reduceOnly, true)
        await store.confirm(wallet: F.wallet)
        let count = await sender.count
        XCTAssertEqual(count, 1)
        for (service, data) in before { XCTAssertEqual(keychain.snapshot[service], data) }
    }

    func testJournalFailureIsNotReportedAsMarketMovementAndNeverSigns() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let reader = OrderStoreReader(), signer = OrderStoreSigner(clock: context.clock), sender = OrderStoreSender()
        await reader.setPosition("0.018")
        let store = try make(context, reader: reader, signer: signer, sender: sender)
        context.keychain.setLocked()
        await store.reviewReduction(percent: 100, slippageBPS: 50, wallet: F.wallet, dex: "xyz", coin: F.coin)
        XCTAssertEqual(store.errorMessage, FundingJournalError.unavailable.orderMessage)
        XCTAssertNotEqual(store.errorMessage, HyperliquidLiveOrderError.changed.localizedDescription)
        await store.confirm(wallet: F.wallet)
        XCTAssertEqual(signer.count, 0)
        let count = await sender.count
        XCTAssertEqual(count, 0)
    }

    func testSeparateVenueBalanceRequiresSetupAndRefreshReadsSharedCapacity() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let reader = OrderStoreReader(), signer = OrderStoreSigner(clock: context.clock), sender = OrderStoreSender()
        let store = try make(context, reader: reader, signer: signer, sender: sender)
        await reader.setMode("default")
        await reader.setAvailableMargin("0")
        await store.loadEntry(wallet: F.wallet, dex: "xyz", coin: F.coin)
        let separate = LiveOrderEntrySummary(account: try XCTUnwrap(store.entryAccount),
            feeRate: try XCTUnwrap(store.entryFeeRate), side: .buy, selectedLeverage: 5)
        XCTAssertTrue(separate.needsSharedBalance)
        XCTAssertEqual(separate.balance, "0")

        await reader.setMode("unifiedAccount")
        await reader.setAvailableMargin("1.946502")
        await store.loadEntry(wallet: F.wallet, dex: "xyz", coin: F.coin)
        var shared = LiveOrderEntrySummary(account: try XCTUnwrap(store.entryAccount),
            feeRate: try XCTUnwrap(store.entryFeeRate), side: .buy, selectedLeverage: 5)
        XCTAssertFalse(shared.needsSharedBalance)
        XCTAssertEqual(shared.balance, "1.946502")
        XCTAssertEqual(shared.openingIssue(margin: "1.946502"), "Minimum order value: 10 USDC".bSmartLocalized)
        shared.selectedLeverage = 10
        XCTAssertNil(shared.openingIssue(margin: "1.5"))
        XCTAssertEqual(shared.openingIssue(margin: "2"), "Insufficient available margin".bSmartLocalized)
        XCTAssertNotEqual(shared.maximumMargin(), "0")
        XCTAssertEqual(signer.count, 0)
        let sends = await sender.count; XCTAssertEqual(sends, 0)
    }

    func testFundedSeparateVenueAndEmptyUnifiedAccountDoNotRequestModeChange() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let reader = OrderStoreReader(), signer = OrderStoreSigner(clock: context.clock), sender = OrderStoreSender()
        let store = try make(context, reader: reader, signer: signer, sender: sender)
        for (mode, balance) in [("default", "2"), ("unifiedAccount", "0"), ("portfolioMargin", "0")] {
            await reader.setMode(mode); await reader.setAvailableMargin(balance)
            await store.loadEntry(wallet: F.wallet, dex: "xyz", coin: F.coin)
            let summary = LiveOrderEntrySummary(account: try XCTUnwrap(store.entryAccount),
                feeRate: try XCTUnwrap(store.entryFeeRate), side: .buy)
            XCTAssertFalse(summary.needsSharedBalance)
        }
        XCTAssertEqual(signer.count, 0)
    }

    func testDepositCTARequiresVerifiedZeroBalanceAndZeroMarketCapacity() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let reader = OrderStoreReader()
        let store = try make(context, reader: reader, signer: OrderStoreSigner(clock: context.clock),
                             sender: OrderStoreSender())
        await reader.setMode("unifiedAccount")
        await reader.setAvailableMargin("0")
        await store.loadEntry(wallet: F.wallet, dex: "xyz", coin: F.coin)
        let summary = LiveOrderEntrySummary(account: try XCTUnwrap(store.entryAccount),
            feeRate: try XCTUnwrap(store.entryFeeRate), side: .buy)
        let now = context.clock.now
        func balance(_ amount: String, accountID: UUID = F.wallet.accountID) throws -> HyperCoreBalanceSnapshot {
            try .init(accountID: accountID, owner: F.wallet.address, mode: .unifiedAccount,
                usdc: .init(amount), held: .init("0"), perps: nil, requestedAt: now, checkedAt: now)
        }
        XCTAssertTrue(summary.shouldOfferDeposit(balance: try balance("0")))
        XCTAssertFalse(summary.shouldOfferDeposit(balance: try balance("1")))
        XCTAssertFalse(summary.shouldOfferDeposit(balance: try balance("0", accountID: UUID())))
        XCTAssertFalse(summary.shouldOfferDeposit(balance: nil))

        await reader.setAvailableMargin("1")
        await store.loadEntry(wallet: F.wallet, dex: "xyz", coin: F.coin)
        let fundedCapacity = LiveOrderEntrySummary(account: try XCTUnwrap(store.entryAccount),
            feeRate: try XCTUnwrap(store.entryFeeRate), side: .buy)
        XCTAssertFalse(fundedCapacity.shouldOfferDeposit(balance: try balance("0")))
    }

    func testOpinionRegistrationFailureCannotSignOrSubmit() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let signer = OrderStoreSigner(clock: context.clock), sender = OrderStoreSender()
        let attribution = OrderAttributionStub(); attribution.rejects = true
        let store = try make(context, reader: OrderStoreReader(), signer: signer, sender: sender, attribution: attribution)
        await store.review(notional: "100", side: .buy, slippageBPS: 50, wallet: F.wallet, dex: "xyz", coin: F.coin)
        await store.confirm(wallet: F.wallet)
        XCTAssertEqual(attribution.orders.count, 1); XCTAssertEqual(signer.count, 0)
        let sends = await sender.count
        XCTAssertEqual(sends, 0); XCTAssertNil(store.result); XCTAssertNotNil(store.errorMessage)
    }

    func testOpinionIsBoundToExactOrderBeforeSigningAndOnlyOnce() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let signer = OrderStoreSigner(clock: context.clock), sender = OrderStoreSender()
        let attribution = OrderAttributionStub()
        attribution.onRegister = { XCTAssertEqual(signer.count, 0) }
        let store = try make(context, reader: OrderStoreReader(), signer: signer, sender: sender, attribution: attribution)
        await store.review(notional: "100", side: .buy, slippageBPS: 50, wallet: F.wallet, dex: "xyz", coin: F.coin)
        let reviewed = try XCTUnwrap(store.preview?.order)
        await store.confirm(wallet: F.wallet)
        await store.confirm(wallet: F.wallet)
        XCTAssertEqual(attribution.orders, [reviewed])
        XCTAssertEqual(store.result?.order.cloid, reviewed.cloid)
        XCTAssertEqual(store.result?.order.size, reviewed.size.wire); XCTAssertEqual(signer.count, 1)
    }

    func testReduceOnlyDoesNotRequireFeedRegistration() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let reader = OrderStoreReader(), signer = OrderStoreSigner(clock: context.clock), sender = OrderStoreSender()
        await reader.setPosition("-0.5")
        let attribution = OrderAttributionStub(); attribution.rejects = true
        let store = try make(context, reader: reader, signer: signer, sender: sender, attribution: attribution)
        await store.reviewReduction(percent: 100, slippageBPS: 50, wallet: F.wallet, dex: "xyz", coin: F.coin)
        await store.confirm(wallet: F.wallet)
        XCTAssertTrue(attribution.orders.isEmpty); XCTAssertNotNil(store.result); XCTAssertEqual(signer.count, 1)
    }

    func testOriginalSlideSubmitsMarginWithActualLeverageOnce() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let reader = OrderStoreReader(), signer = OrderStoreSigner(clock: context.clock), sender = OrderStoreSender()
        let store = try make(context, reader: reader, signer: signer, sender: sender)
        await store.executeMargin("10", leverage: 10, side: .buy, wallet: F.wallet, dex: "xyz", coin: F.coin)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.result?.state, .filled)
        XCTAssertEqual(store.result?.order.size, "0.454")
        let reads = await reader.reads
        // One immediate slide review and an independent post-sign snapshot.
        XCTAssertEqual(reads, 15)
        await store.executeMargin("10", leverage: 10, side: .buy, wallet: F.wallet, dex: "xyz", coin: F.coin)
        let sends = await sender.count
        XCTAssertEqual(sends, 1); XCTAssertEqual(signer.count, 1)
    }

    func testSameSlideStillRejectsBalanceAndModeChangesAfterSigning() async throws {
        for changeMode in [false, true] {
            let context = OrderLifecycleContext(); defer { context.cleanup() }
            let reader = OrderStoreReader(), signer = OrderStoreSigner(clock: context.clock), sender = OrderStoreSender()
            let store = try make(context, reader: reader, signer: signer, sender: sender)
            signer.afterSigning = {
                if changeMode { await reader.setMode("default") }
                else { await reader.setAvailableMargin("0") }
            }
            await store.executeMargin("10", leverage: 10, side: .buy, wallet: F.wallet, dex: "xyz", coin: F.coin)
            XCTAssertNil(store.result); XCTAssertNotNil(store.errorMessage)
            XCTAssertEqual(signer.count, 1)
            let sends = await sender.count
            XCTAssertEqual(sends, 0)
            let records = try await context.journal().orderRecords(wallet: F.wallet)
            XCTAssertEqual(records.first?.state, .signed)
        }
    }

    func testOpeningAlsoStopsWhenPositionChangesAfterSigning() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let reader = OrderStoreReader(), signer = OrderStoreSigner(clock: context.clock), sender = OrderStoreSender()
        let store = try make(context, reader: reader, signer: signer, sender: sender)
        signer.afterSigning = { await reader.setPosition("-0.5") }
        await store.executeMargin("10", leverage: 10, side: .buy, wallet: F.wallet, dex: "xyz", coin: F.coin)
        XCTAssertNil(store.result); XCTAssertNotNil(store.errorMessage)
        let sends = await sender.count
        XCTAssertEqual(sends, 0)
    }

    func testSlowAttributionCannotRefreshSameSlideProofOrSignAnExpiredReview() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let reader = OrderStoreReader(), signer = OrderStoreSigner(clock: context.clock), sender = OrderStoreSender()
        let attribution = OrderAttributionStub()
        attribution.onRegister = { context.clock.advance(wall: 6, steady: .seconds(6)) }
        let store = try make(context, reader: reader, signer: signer, sender: sender, attribution: attribution)
        await store.executeMargin("10", leverage: 10, side: .buy, wallet: F.wallet, dex: "xyz", coin: F.coin)
        XCTAssertNil(store.result); XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(signer.count, 0)
        let sends = await sender.count
        XCTAssertEqual(sends, 0)
    }

    func testUnifiedSlideReducesEitherSideOnceWithoutChangingLeverage() async throws {
        for position in ["-2.503", "2.503"] {
            let context = OrderLifecycleContext(); defer { context.cleanup() }
            let reader = OrderStoreReader(), signer = OrderStoreSigner(clock: context.clock), sender = OrderStoreSender()
            await reader.setPosition(position)
            await reader.setAvailableMargin("0")
            let leverage = ComposerLeverageStub(clock: context.clock)
            let store = try HyperliquidMarketOrderStore(service: OrderStoreAccount(clock: context.clock),
                journal: context.journal(), reader: reader, signer: signer, broadcaster: sender,
                leverageSigner: leverage, leverageSender: leverage, clock: { context.clock.now },
                continuousClock: { context.clock.instant }, enabled: { true })
            await store.loadEntry(wallet: F.wallet, dex: "xyz", coin: F.coin)
            let summary = LiveOrderEntrySummary(account: try XCTUnwrap(store.entryAccount),
                feeRate: try XCTUnwrap(store.entryFeeRate), side: .buy)
            XCTAssertEqual(summary.reductionQuantity(percent: 25), "0.625")
            XCTAssertEqual(summary.reductionQuantity(percent: 100), "2.503")
            XCTAssertNil(summary.reductionQuantity(percent: 101))
            await store.executeReduction(percent: 25, wallet: F.wallet, dex: "xyz", coin: F.coin)
            XCTAssertNil(store.errorMessage)
            XCTAssertEqual(store.result?.order.size, "0.625")
            XCTAssertEqual(store.result?.order.reduceOnly, true)
            XCTAssertEqual(store.result?.order.side, position.hasPrefix("-") ? .buy : .sell)
            await store.executeReduction(percent: 25, wallet: F.wallet, dex: "xyz", coin: F.coin)
            let sends = await sender.count
            XCTAssertEqual(sends, 1); XCTAssertEqual(signer.count, 1); XCTAssertEqual(leverage.sends, 0)
        }
    }

    func testUnifiedSlideFullClosePreservesExactPositionSize() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let reader = OrderStoreReader(), signer = OrderStoreSigner(clock: context.clock), sender = OrderStoreSender()
        await reader.setPosition("-2.503")
        let store = try make(context, reader: reader, signer: signer, sender: sender)
        await store.executeReduction(percent: 100, wallet: F.wallet, dex: "xyz", coin: F.coin)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.result?.order.size, "2.503")
        XCTAssertEqual(store.result?.order.reduceOnly, true)
    }

    func testUnifiedReductionRejectsInvalidPercentAndMissingPosition() async throws {
        for percent in [0, 101, 100] {
            let context = OrderLifecycleContext(); defer { context.cleanup() }
            let reader = OrderStoreReader(), signer = OrderStoreSigner(clock: context.clock), sender = OrderStoreSender()
            if percent != 100 { await reader.setPosition("-2.503") }
            let store = try make(context, reader: reader, signer: signer, sender: sender)
            await store.executeReduction(percent: percent, wallet: F.wallet, dex: "xyz", coin: F.coin)
            XCTAssertNil(store.result); XCTAssertNotNil(store.errorMessage)
            let sends = await sender.count
            XCTAssertEqual(sends, 0); XCTAssertEqual(signer.count, 0)
        }
    }

    func testLeverageMustBeConfirmedOnExchangeBeforeOrder() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let reader = OrderStoreReader(), signer = OrderStoreSigner(clock: context.clock), sender = OrderStoreSender()
        let leverage = ComposerLeverageStub(clock: context.clock)
        let store = try HyperliquidMarketOrderStore(service: OrderStoreAccount(clock: context.clock),
            journal: context.journal(), reader: reader, signer: signer, broadcaster: sender,
            leverageSigner: leverage, leverageSender: leverage, clock: { context.clock.now },
            continuousClock: { context.clock.instant }, enabled: { true })
        // Stub says OK but leaves exchange leverage unchanged: no order may follow.
        await store.executeMargin("10", leverage: 5, side: .buy, wallet: F.wallet, dex: "xyz", coin: F.coin)
        XCTAssertNil(store.result); XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(leverage.sends, 1); XCTAssertEqual(signer.count, 0)
        let sends = await sender.count; XCTAssertEqual(sends, 0)
    }

    func testOriginalSlideUpdatesLeverageThenSubmitsOnlyOneOrder() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let reader = OrderStoreReader(), signer = OrderStoreSigner(clock: context.clock), sender = OrderStoreSender()
        let leverage = ComposerLeverageStub(clock: context.clock)
        leverage.afterSubmission = { await reader.setLeverage(5) }
        let store = try HyperliquidMarketOrderStore(service: OrderStoreAccount(clock: context.clock),
            journal: context.journal(), reader: reader, signer: signer, broadcaster: sender,
            leverageSigner: leverage, leverageSender: leverage, clock: { context.clock.now },
            continuousClock: { context.clock.instant }, enabled: { true })
        await store.executeMargin("10", leverage: 5, side: .buy, wallet: F.wallet, dex: "xyz", coin: F.coin)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.result?.state, .filled)
        XCTAssertEqual(store.result?.order.size, "0.227")
        XCTAssertEqual(store.entryAccount?.active.leverage.multiplier, 5)
        let reads = await reader.reads
        XCTAssertEqual(reads, 20) // One extra authoritative read-back after changing leverage.
        await store.executeMargin("10", leverage: 5, side: .buy, wallet: F.wallet, dex: "xyz", coin: F.coin)
        XCTAssertEqual(leverage.sends, 1); XCTAssertEqual(signer.count, 1)
        let sends = await sender.count; XCTAssertEqual(sends, 1)
    }

    func testComposerContextReadsActualLeverageAndBalanceWithoutOrderAuthority() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let reader = OrderStoreReader(), signer = OrderStoreSigner(clock: context.clock), sender = OrderStoreSender()
        await reader.setAvailableMargin("2.99418")
        let store = try make(context, reader: reader, signer: signer, sender: sender)
        await store.loadEntry(wallet: F.wallet, dex: "xyz", coin: F.coin)
        XCTAssertNil(store.entryError)
        let snapshot = try XCTUnwrap(store.entryAccount)
        XCTAssertEqual(snapshot.active.buy.availableToTrade.wire, "2.99418")
        let summary = LiveOrderEntrySummary(account: snapshot, feeRate: try XCTUnwrap(store.entryFeeRate), side: .buy)
        let maximum = try HyperliquidOrderDecimal(XCTUnwrap(summary.maximumNotional(slippageBPS: 50)))
        let margin = try HyperliquidExactValue(maximum).divided(by: .init(UInt64(summary.leverage)))
        let fee = try HyperliquidExactValue(maximum).multiplied(by: summary.feeRate)
        XCTAssertLessThanOrEqual(try margin.adding(fee), HyperliquidExactValue(snapshot.active.buy.availableToTrade))
        XCTAssertNil(store.preview); XCTAssertNil(store.result); XCTAssertEqual(signer.count, 0)
        await store.confirm(wallet: F.wallet)
        let sends = await sender.count
        XCTAssertEqual(sends, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: context.directory.appendingPathComponent("transactions.sqlite").path))
        store.clearEntry()
        XCTAssertNil(store.entryAccount); XCTAssertNil(store.entryFeeRate)
    }

    func testComposerContextWithDisabledTradingNeverReadsOrSigns() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let reader = OrderStoreReader(), signer = OrderStoreSigner(clock: context.clock), sender = OrderStoreSender()
        let store = try make(context, reader: reader, signer: signer, sender: sender, enabled: { false })
        await store.loadEntry(wallet: F.wallet, dex: "xyz", coin: F.coin)
        XCTAssertNil(store.entryAccount); XCTAssertNil(store.entryFeeRate)
        let reads = await reader.reads
        XCTAssertEqual(reads, 0); XCTAssertEqual(signer.count, 0)
    }

    func testDisabledTradingNeverReadsMarketOrSigns() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let reader = OrderStoreReader(), signer = OrderStoreSigner(clock: context.clock), sender = OrderStoreSender()
        let store = try make(context, reader: reader, signer: signer, sender: sender, enabled: { false })
        await store.review(notional: "100", side: .buy, slippageBPS: 50, wallet: F.wallet, dex: "xyz", coin: F.coin)
        XCTAssertNil(store.preview)
        XCTAssertNotNil(store.errorMessage)
        let reads = await reader.reads, sends = await sender.count
        XCTAssertEqual(reads, 0); XCTAssertEqual(signer.count, 0); XCTAssertEqual(sends, 0)
    }

    func testExplicitConfirmationReachesDeviceSignerAndRealTransportBoundaryOnce() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let reader = OrderStoreReader(), signer = OrderStoreSigner(clock: context.clock), sender = OrderStoreSender()
        let store = try make(context, reader: reader, signer: signer, sender: sender)
        await store.review(notional: "100", side: .buy, slippageBPS: 50, wallet: F.wallet, dex: "xyz", coin: F.coin)
        XCTAssertNotNil(store.preview)
        XCTAssertEqual(signer.count, 0)
        await store.confirm(wallet: F.wallet)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.result?.state, .filled)
        XCTAssertEqual(signer.count, 1)
        await store.confirm(wallet: F.wallet)
        let sends = await sender.count
        XCTAssertEqual(sends, 1)
        let records = try await context.journal().orderRecords(wallet: F.wallet)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.acknowledgement, store.result?.acknowledgement)
    }

    func testCancellationAfterSignaturePreservesEvidenceWithoutSubmitting() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let reader = OrderStoreReader(), signer = OrderStoreSigner(clock: context.clock), sender = OrderStoreSender()
        let store = try make(context, reader: reader, signer: signer, sender: sender)
        signer.afterSigning = { withUnsafeCurrentTask { $0?.cancel() } }
        await store.review(notional: "100", side: .buy, slippageBPS: 50, wallet: F.wallet, dex: "xyz", coin: F.coin)
        let task = Task { await store.confirm(wallet: F.wallet) }
        await task.value
        let records = try await context.journal().orderRecords(wallet: F.wallet)
        XCTAssertEqual(records.first?.state, .signed)
        XCTAssertNotNil(records.first?.signature)
        let sends = await sender.count
        XCTAssertEqual(sends, 0)
    }

    func testConfirmationReturnsBeforeOptionalFillQueries() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let reader = OrderStoreReader(), signer = OrderStoreSigner(clock: context.clock), sender = OrderStoreSender()
        let store = try make(context, reader: reader, signer: signer, sender: sender)
        await store.review(notional: "100", side: .buy, slippageBPS: 50, wallet: F.wallet, dex: "xyz", coin: F.coin)
        let order = try XCTUnwrap(store.preview?.order)
        await reader.setFills(try OrderFillFixture.data([OrderFillFixture.row([
            "sz": order.size.wire, "px": "220", "fee": "0.012345", "cloid": order.cloid])]))
        await store.confirm(wallet: F.wallet)
        let id = try XCTUnwrap(store.result?.id)
        XCTAssertNil(store.errorMessage)
        XCTAssertNil(store.fills[id])
        let before = try await context.journal().orderFillSummaries(wallet: F.wallet)
        XCTAssertEqual(before[id]?.fills.count, 0)
        let automaticFillReads = await reader.fillReads
        XCTAssertEqual(automaticFillReads, 0)
        await store.reconcile(try XCTUnwrap(store.result), wallet: F.wallet)
        XCTAssertEqual(store.fills[id]?.complete, true)
        XCTAssertEqual(store.fills[id]?.fee, "0.012345")
        XCTAssertEqual(store.fills[id]?.averagePrice?.wire, "220")
        XCTAssertEqual(signer.count, 1)
        let sends = await sender.count
        XCTAssertEqual(sends, 1)
        let persisted = try await context.journal().orderFillSummaries(wallet: F.wallet)
        XCTAssertEqual(persisted[id]?.fee, "0.012345")
    }

    func testLostResponseNeverBecomesPaperFill() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let reader = OrderStoreReader(), signer = OrderStoreSigner(clock: context.clock), sender = OrderStoreSender(uncertain: true)
        let store = try make(context, reader: reader, signer: signer, sender: sender)
        await store.review(notional: "100", side: .buy, slippageBPS: 50, wallet: F.wallet, dex: "xyz", coin: F.coin)
        await store.confirm(wallet: F.wallet)
        XCTAssertEqual(store.result?.state, .uncertain)
        XCTAssertNil(store.result?.acknowledgement)
        await store.review(notional: "100", side: .buy, slippageBPS: 50, wallet: F.wallet, dex: "xyz", coin: F.coin)
        await store.confirm(wallet: F.wallet)
        let sends = await sender.count
        XCTAssertEqual(sends, 1)
    }

    func testChangedWalletBindingPreventsSigning() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let service = OrderStoreAccount(clock: context.clock), reader = OrderStoreReader()
        let signer = OrderStoreSigner(clock: context.clock), sender = OrderStoreSender()
        let store = try make(context, service: service, reader: reader, signer: signer, sender: sender)
        await store.review(notional: "100", side: .buy, slippageBPS: 50, wallet: F.wallet, dex: "xyz", coin: F.coin)
        service.address = HyperliquidQuoteFixture.recipient
        await store.confirm(wallet: F.wallet)
        XCTAssertEqual(signer.count, 0)
        XCTAssertNotNil(store.errorMessage)
    }

    func testReductionRequiresReviewAndPreservesReduceOnlyThroughSigning() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let reader = OrderStoreReader(), signer = OrderStoreSigner(clock: context.clock), sender = OrderStoreSender()
        await reader.setPosition("-2.503")
        let store = try make(context, reader: reader, signer: signer, sender: sender)
        await store.reviewReduction(percent: 25, slippageBPS: 50, wallet: F.wallet, dex: "xyz", coin: F.coin)
        XCTAssertEqual(store.preview?.order.size.wire, "0.625")
        XCTAssertEqual(store.preview?.order.side, .buy)
        XCTAssertEqual(store.preview?.order.reduceOnly, true)
        XCTAssertEqual(signer.count, 0)
        await store.confirm(wallet: F.wallet)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.result?.state, .filled)
        XCTAssertEqual(store.result?.order.reduceOnly, true)
        XCTAssertEqual(signer.count, 1)
        await store.confirm(wallet: F.wallet)
        let sends = await sender.count
        XCTAssertEqual(sends, 1)
    }

    func testChangedPositionRequiresNewReviewBeforeSigning() async throws {
        for changed in ["-0.5", "-3", "2.5", nil] as [String?] {
            let context = OrderLifecycleContext(); defer { context.cleanup() }
            let reader = OrderStoreReader(), signer = OrderStoreSigner(clock: context.clock), sender = OrderStoreSender()
            await reader.setPosition("-2.5")
            let store = try make(context, reader: reader, signer: signer, sender: sender)
            await store.reviewReduction(percent: 25, slippageBPS: 50, wallet: F.wallet, dex: "xyz", coin: F.coin)
            XCTAssertNotNil(store.preview)
            await reader.setPosition(changed)
            await store.confirm(wallet: F.wallet)
            XCTAssertNotNil(store.errorMessage)
            XCTAssertEqual(signer.count, 0)
            let sends = await sender.count
            XCTAssertEqual(sends, 0)
        }
    }

    func testNoPositionAndInvalidatedReviewNeverSign() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let reader = OrderStoreReader(), signer = OrderStoreSigner(clock: context.clock), sender = OrderStoreSender()
        let store = try make(context, reader: reader, signer: signer, sender: sender)
        await store.reviewReduction(percent: 100, slippageBPS: 50, wallet: F.wallet, dex: "xyz", coin: F.coin)
        XCTAssertNil(store.preview)
        XCTAssertEqual(store.errorMessage, HyperliquidLiveOrderError.noPosition.localizedDescription)
        await reader.setPosition("-0.5")
        await store.reviewReduction(percent: 100, slippageBPS: 50, wallet: F.wallet, dex: "xyz", coin: F.coin)
        XCTAssertNotNil(store.preview)
        store.invalidate()
        await store.confirm(wallet: F.wallet)
        XCTAssertEqual(signer.count, 0)
        let sends = await sender.count
        XCTAssertEqual(sends, 0)
    }

    func testDisabledReductionNeverReadsMarket() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let reader = OrderStoreReader(), signer = OrderStoreSigner(clock: context.clock), sender = OrderStoreSender()
        let store = try make(context, reader: reader, signer: signer, sender: sender, enabled: { false })
        await store.reviewReduction(percent: 100, slippageBPS: 50, wallet: F.wallet, dex: "xyz", coin: F.coin)
        XCTAssertNil(store.preview)
        let reads = await reader.reads
        XCTAssertEqual(reads, 0)
        XCTAssertEqual(signer.count, 0)
    }

    func testPositionChangeAfterSigningRetainsSignatureWithoutSubmitting() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let reader = OrderStoreReader(), signer = OrderStoreSigner(clock: context.clock), sender = OrderStoreSender()
        await reader.setPosition("-0.5")
        let store = try make(context, reader: reader, signer: signer, sender: sender)
        signer.afterSigning = { await reader.setPosition("0.5") }
        await store.reviewReduction(percent: 100, slippageBPS: 50, wallet: F.wallet, dex: "xyz", coin: F.coin)
        await store.confirm(wallet: F.wallet)
        XCTAssertNotNil(store.errorMessage)
        let records = try await context.journal().orderRecords(wallet: F.wallet)
        XCTAssertEqual(records.first?.state, .signed)
        XCTAssertEqual(records.first?.order.reduceOnly, true)
        XCTAssertNotNil(records.first?.signature)
        let sends = await sender.count
        XCTAssertEqual(sends, 0)
    }

    func testReductionWithoutNewMarginAllowsPartialDepthAndPreservesRequestedSize() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let reader = OrderStoreReader(), signer = OrderStoreSigner(clock: context.clock), sender = OrderStoreSender(filledSize: "3")
        await reader.setPosition("-4")
        await reader.setAvailableMargin("0")
        let store = try make(context, reader: reader, signer: signer, sender: sender)
        await store.reviewReduction(percent: 100, slippageBPS: 50, wallet: F.wallet, dex: "xyz", coin: F.coin)
        let preview = try XCTUnwrap(store.preview)
        XCTAssertFalse(preview.quote.fullyCovered)
        XCTAssertEqual(preview.quote.quotedSize, HyperliquidExactValue(3))
        XCTAssertEqual(preview.quote.uncoveredSize, HyperliquidExactValue(1))
        XCTAssertEqual(preview.order.size.wire, "4")
        XCTAssertTrue(preview.order.reduceOnly)
        XCTAssertEqual(signer.count, 0)
        await store.confirm(wallet: F.wallet)
        XCTAssertNil(store.errorMessage)
        guard case .filled(let fill) = store.result?.acknowledgement else { return XCTFail("Expected partial IOC acknowledgement") }
        XCTAssertEqual(fill.size.wire, "3")
        XCTAssertFalse(fill.isComplete)
        XCTAssertEqual(store.result?.order.size, "4")
    }

    func testOpeningStillRequiresFullDepthCoverage() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let reader = OrderStoreReader(), signer = OrderStoreSigner(clock: context.clock), sender = OrderStoreSender()
        let store = try make(context, reader: reader, signer: signer, sender: sender)
        await store.review(notional: "1000", side: .buy, slippageBPS: 50, wallet: F.wallet, dex: "xyz", coin: F.coin)
        XCTAssertNil(store.preview)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(signer.count, 0)
    }

    private func make(_ context: OrderLifecycleContext, service: OrderStoreAccount? = nil,
                      reader: OrderStoreReader, signer: OrderStoreSigner, sender: OrderStoreSender,
                      attribution: (any OpinionOrderAttributing)? = nil,
                      enabled: @escaping () -> Bool = { true }) throws -> HyperliquidMarketOrderStore {
        try .init(service: service ?? OrderStoreAccount(clock: context.clock), journal: context.journal(),
            reader: reader, signer: signer, broadcaster: sender, attribution: attribution, clock: { context.clock.now },
            continuousClock: { context.clock.instant }, enabled: enabled)
    }
}

@MainActor
private final class OrderAttributionStub: OpinionOrderAttributing {
    var orders: [HyperliquidOrderIntent] = []
    var rejects = false
    var onRegister: (() -> Void)?
    var afterRegister: (() async -> Void)?
    func register(order: HyperliquidOrderIntent) async throws {
        orders.append(order); onRegister?()
        await afterRegister?()
        if rejects { throw AccountAccessError.unavailable }
    }
    func synchronize(order: HyperliquidOrderIntent) async { }
}

@MainActor
final class OrderStoreAccount: AccountWalletServicing {
    let clock: TradingCheckClock
    var walletAccountID: UUID? = HyperliquidTradingFixture.wallet.accountID
    var walletSessionRevision = UUID()
    var walletSessionIsRefreshing = false
    var expiredRegistrationOnce = false
    var registrationAttempts = 0
    var address: String? = HyperliquidTradingFixture.wallet.address
    init(clock: TradingCheckClock) { self.clock = clock }
    func walletRegistration() async throws -> TradingWalletRegistration {
        registrationAttempts += 1
        if expiredRegistrationOnce {
            expiredRegistrationOnce = false
            throw AccountAccessError.expired
        }
        return .init(accountId: HyperliquidTradingFixture.wallet.accountID, address: address)
    }
    func fundingSigningLease(wallet: DeviceWalletSummary) throws -> FundingSigningLease {
        .init(wallet: wallet, clock: { self.clock.now }, continuousNow: { self.clock.instant })
    }
    func walletChallenge(address: String) async throws -> TradingWalletChallenge { throw DeviceWalletError.invalidProof }
    func bindWallet(challenge: TradingWalletChallenge, signature: String) async throws -> TradingWalletRegistration { throw DeviceWalletError.invalidProof }
}

actor OrderStoreReader: HyperliquidExecutionReading {
    typealias F = HyperliquidTradingFixture
    typealias Q = HyperliquidQuoteFixture
    private(set) var reads = 0
    private(set) var fillReads = 0
    private var position: String?
    private var mode = "unifiedAccount"
    private var availableMargin: String?
    private var leverage = 10
    private var stalePositionOnce = false
    private var failDexOnce = false
    private var fillData = Data("[]".utf8)
    private let clock: TradingCheckClock?
    init(clock: TradingCheckClock? = nil) { self.clock = clock }
    func setPosition(_ size: String?) { position = size }
    func setMode(_ value: String) { mode = value }
    func setAvailableMargin(_ amount: String) { availableMargin = amount }
    func setLeverage(_ value: Int) { leverage = value }
    func staleNextPosition() { stalePositionOnce = true }
    func failNextDexRead() { failDexOnce = true }
    func setFills(_ data: Data) { fillData = data }
    func read(_ query: HyperliquidExecutionQuery) throws -> Data {
        reads += 1
        switch query {
        case .fills: fillReads += 1; return fillData
        case .dexs:
            if failDexOnce { failDexOnce = false; throw HyperliquidTradingCheckError.unavailable }
            return HyperliquidOrderTestSupport.dexs
        case .metadata:
            return try F.data(["collateralToken": 0, "universe": [["name": F.coin, "szDecimals": 3, "maxLeverage": 20,
                "marginMode": "normal", "deployerFeeScale": "1.0", "growthMode": "enabled"]]])
        case .mode: return try F.data(mode)
        case .active: return try F.active(leverage: F.leverage("cross", leverage),
            overrides: availableMargin.map { ["availableToTrade": [$0, $0]] } ?? [:])
        case .positions:
            if stalePositionOnce {
                stalePositionOnce = false
                clock?.advance(wall: 6, steady: .seconds(6))
            }
            return try F.positions(rows: position.map { [F.row(size: $0, leverage: F.leverage("cross", leverage))] } ?? [],
                                   at: clock?.now ?? F.now)
        case .book: return try Q.book(at: clock?.now ?? F.now)
        case .fees: return try Q.fees()
        default: throw HyperliquidTradingCheckError.invalidResponse
        }
    }
}

@MainActor
private final class OrderStoreSigner: HyperliquidDeviceSigning {
    let clock: TradingCheckClock
    var count = 0
    var afterSigning: (() async -> Void)?
    init(clock: TradingCheckClock) { self.clock = clock }
    func signOrder(_ permit: HyperliquidOrderSigningPermit, lease: FundingSigningLease) async throws -> String {
        try permit.consume(wallet: lease.wallet, now: clock.now, continuousNow: clock.instant)
        let signature = try lease.perform(wallet: lease.wallet) {
            let key = try XCTUnwrap(PrivateKey(data: Data(repeating: 0, count: 31) + Data([1])))
            let raw = EthereumMessageSigner.signTypedMessage(privateKey: key, messageJson: try HyperliquidOrderCodec.typedJSON(permit.preview.order))
            return raw.hasPrefix("0x") ? raw : "0x" + raw
        }
        count += 1; await afterSigning?()
        return signature
    }
}

private actor OrderStoreSender: HyperliquidOrderBroadcasting {
    private(set) var count = 0
    let uncertain: Bool
    let filledSize: String?
    init(uncertain: Bool = false, filledSize: String? = nil) { self.uncertain = uncertain; self.filledSize = filledSize }
    func submit(_ permit: HyperliquidOrderSubmissionPermit, lease: FundingSigningLease) throws -> Data? {
        _ = try permit.start(lease: lease) { $0 }
        count += 1
        if uncertain { return nil }
        return Data("""
        {"status":"ok","response":{"type":"order","data":{"statuses":[{"filled":{"totalSz":"\(filledSize ?? permit.order.size.wire)","avgPx":"220","oid":25}}]}}}
        """.utf8)
    }
}

@MainActor
private final class ComposerLeverageStub: HyperliquidLeverageSigning, HyperliquidLeverageBroadcasting {
    let clock: TradingCheckClock
    var sends = 0
    var afterSubmission: (() async -> Void)?
    init(clock: TradingCheckClock) { self.clock = clock }
    func signLeverage(_ permit: HyperliquidLeveragePermit, lease: FundingSigningLease) throws -> String {
        try permit.consume(wallet: lease.wallet, now: clock.now)
        let key = try XCTUnwrap(PrivateKey(data: Data(repeating: 0, count: 31) + Data([1])))
        let raw = EthereumMessageSigner.signTypedMessage(privateKey: key, messageJson: try HyperliquidLeverageCodec.typedJSON(permit.update))
        let signature = raw.hasPrefix("0x") ? raw : "0x" + raw
        _ = try HyperliquidLeverageCodec.envelope(permit.update, signature: signature)
        return signature
    }
    func submit(_ permit: HyperliquidLeveragePermit, signature: String, lease: FundingSigningLease) async -> Data? {
        sends += 1
        await afterSubmission?()
        return Data(#"{"status":"ok","response":{"type":"default"}}"#.utf8)
    }
}
