import XCTest
import WalletCore
@testable import BSmart

@MainActor
final class HyperliquidMarketOrderStoreTests: XCTestCase {
    typealias F = HyperliquidTradingFixture

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
                      enabled: @escaping () -> Bool = { true }) throws -> HyperliquidMarketOrderStore {
        try .init(service: service ?? OrderStoreAccount(clock: context.clock), journal: context.journal(),
            reader: reader, signer: signer, broadcaster: sender, clock: { context.clock.now },
            continuousClock: { context.clock.instant }, enabled: enabled)
    }
}

@MainActor
final class OrderStoreAccount: AccountWalletServicing {
    let clock: TradingCheckClock
    var walletAccountID: UUID? = HyperliquidTradingFixture.wallet.accountID
    var address: String? = HyperliquidTradingFixture.wallet.address
    init(clock: TradingCheckClock) { self.clock = clock }
    func walletRegistration() async throws -> TradingWalletRegistration {
        .init(accountId: HyperliquidTradingFixture.wallet.accountID, address: address)
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
    private var availableMargin: String?
    private var fillData = Data("[]".utf8)
    func setPosition(_ size: String?) { position = size }
    func setAvailableMargin(_ amount: String) { availableMargin = amount }
    func setFills(_ data: Data) { fillData = data }
    func read(_ query: HyperliquidExecutionQuery) throws -> Data {
        reads += 1
        switch query {
        case .fills: fillReads += 1; return fillData
        case .dexs: return HyperliquidOrderTestSupport.dexs
        case .metadata:
            return try F.data(["collateralToken": 0, "universe": [["name": F.coin, "szDecimals": 3, "maxLeverage": 20,
                "marginMode": "normal", "deployerFeeScale": "1.0", "growthMode": "enabled"]]])
        case .mode: return try F.data("unifiedAccount")
        case .active: return try F.active(overrides: availableMargin.map { ["availableToTrade": [$0, $0]] } ?? [:])
        case .positions: return try F.positions(rows: position.map { [F.row(size: $0)] } ?? [])
        case .book: return try Q.book()
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
