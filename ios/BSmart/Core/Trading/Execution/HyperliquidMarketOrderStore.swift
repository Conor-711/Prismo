import Foundation
import Combine

@MainActor
final class HyperliquidMarketOrderStore: ObservableObject {
    @Published private(set) var preview: HyperliquidOrderPreview?
    @Published private(set) var result: HyperliquidOrderRecord?
    @Published private(set) var history: [HyperliquidOrderRecord] = []
    @Published private(set) var fills: [UUID: HyperliquidFillSummary] = [:]
    @Published private(set) var isBusy = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var entryAccount: HyperliquidTradingSnapshot?
    @Published private(set) var entryFeeRate: HyperliquidExactValue?
    @Published private(set) var isLoadingEntry = false
    @Published private(set) var entryError: String?
    private let service: any AccountWalletServicing
    private let reader: any HyperliquidExecutionReading
    private let journal: FundingTransactionJournal
    private let signer: any HyperliquidDeviceSigning
    private let broadcaster: any HyperliquidOrderBroadcasting
    private let enabled: () -> Bool
    private let clock: @Sendable () -> Date
    private let continuousClock: @Sendable () -> ContinuousClock.Instant
    private var revision = UUID()
    private var lease: FundingSigningLease?
    private var activeOperation = false
    private var entryRevision = UUID()

    init(service: any AccountWalletServicing, journal: FundingTransactionJournal,
         reader: any HyperliquidExecutionReading = HyperliquidExecutionReader(),
         signer: any HyperliquidDeviceSigning = KeychainDeviceWalletVault(),
         broadcaster: any HyperliquidOrderBroadcasting = HyperliquidOrderBroadcaster(),
         clock: @escaping @Sendable () -> Date = { Date() },
         continuousClock: @escaping @Sendable () -> ContinuousClock.Instant = { .now }, enabled: @escaping () -> Bool) {
        self.service = service; self.journal = journal; self.reader = reader; self.signer = signer
        self.broadcaster = broadcaster; self.enabled = enabled; self.clock = clock; self.continuousClock = continuousClock
    }

    func invalidate() {
        revision = UUID(); lease?.invalidate(); lease = nil; preview = nil
    }

    func clearEntry() {
        entryRevision = UUID(); entryAccount = nil; entryFeeRate = nil
        entryError = nil; isLoadingEntry = false
    }

    // Display context only. Review and confirmation still fetch and validate their own snapshots.
    func loadEntry(wallet: DeviceWalletSummary, dex: String, coin: String) async {
        guard !isLoadingEntry, !activeOperation else { return }
        let request = UUID()
        entryRevision = request; isLoadingEntry = true; entryError = nil
        defer { if entryRevision == request { isLoadingEntry = false } }
        func validate() throws {
            try Task.checkCancellation()
            guard enabled(), entryRevision == request, wallet.canAuthorizeTransactions,
                  service.walletAccountID == wallet.accountID else { throw DeviceWalletError.accountChanged }
        }
        do {
            try validate()
            let registration = try await service.walletRegistration()
            try validate()
            guard registration.accountId == wallet.accountID, registration.address == wallet.address else {
                throw DeviceWalletError.accountChanged
            }
            let snapshot = try await accountSnapshot(wallet: wallet, dex: dex, coin: coin)
            let fees = try HyperliquidTakerFees.decode(await reader.read(.fees(owner: wallet.address)), owner: wallet.address)
            try validate()
            try snapshot.validate(wallet: wallet, now: clock(), continuousNow: continuousClock())
            guard entryRevision == request else { return }
            entryFeeRate = try fees.rate(market: snapshot.market)
            entryAccount = snapshot
        } catch {
            guard entryRevision == request else { return }
            entryAccount = nil; entryFeeRate = nil
            if !(error is CancellationError) { entryError = message(error) }
        }
    }

    func loadHistory(wallet: DeviceWalletSummary) async {
        let token = revision
        do {
            let records = try await journal.orderRecords(wallet: wallet)
            let summaries = try await journal.orderFillSummaries(wallet: wallet)
            guard token == revision, service.walletAccountID == wallet.accountID else { return }
            history = records; fills = summaries
        } catch { if token == revision { errorMessage = FundingJournalError.unavailable.localizedDescription } }
    }

    func reconcile(_ record: HyperliquidOrderRecord, wallet: DeviceWalletSummary) async {
        guard !activeOperation else { return }
        activeOperation = true; isBusy = true; errorMessage = nil
        let token = revision
        defer { activeOperation = false; isBusy = false }
        do {
            guard service.walletAccountID == wallet.accountID else { throw DeviceWalletError.accountChanged }
            let records = try await journal.orderRecords(wallet: wallet)
            guard var resolved = records.first(where: { $0.id == record.id }) else { throw FundingJournalError.conflict }
            if [.submitting, .uncertain].contains(resolved.state) {
                let response = try await reader.read(.orderStatus(owner: wallet.address, cloid: resolved.order.cloid))
                resolved = try await journal.reconcileOrder(id: resolved.id, response: response, wallet: wallet)
            }
            if token == revision, service.walletAccountID == wallet.accountID { result = resolved }
            try Task.checkCancellation()
            guard token == revision, service.walletAccountID == wallet.accountID else { throw DeviceWalletError.accountChanged }
            try await readFills(resolved, wallet: wallet)
        } catch { if token == revision { errorMessage = "Fill verification is incomplete. Your order will not be resent.".bSmartLocalized } }
        if token == revision {
            if service.walletAccountID == wallet.accountID { await loadHistory(wallet: wallet) }
            else { result = nil; history = []; fills = [:]; errorMessage = nil }
        }
    }

    func review(notional: String, side: HyperliquidOrderIntent.Side, slippageBPS: UInt64,
                wallet: DeviceWalletSummary, dex: String, coin: String) async {
        await review(wallet: wallet, dex: dex, coin: coin) { snapshot, book, nonce in
            try HyperliquidMarketOrderPlan.order(notional: notional, side: side, slippageBPS: slippageBPS,
                wallet: wallet, snapshot: snapshot, book: book, nonce: nonce)
        }
    }

    func reviewReduction(percent: Int, slippageBPS: UInt64, wallet: DeviceWalletSummary, dex: String, coin: String) async {
        await review(wallet: wallet, dex: dex, coin: coin) { snapshot, book, nonce in
            try HyperliquidMarketOrderPlan.reduction(percent: percent, slippageBPS: slippageBPS,
                wallet: wallet, snapshot: snapshot, book: book, nonce: nonce)
        }
    }

    private func review(wallet: DeviceWalletSummary, dex: String, coin: String,
                        makeOrder: (HyperliquidTradingSnapshot, HyperliquidOrderBook, UInt64) throws -> HyperliquidOrderIntent) async {
        guard !activeOperation else { return }
        activeOperation = true; isBusy = true; errorMessage = nil; preview = nil; result = nil
        let token = revision
        defer { activeOperation = false; isBusy = false }
        do {
            try await verify(wallet: wallet, token: token)
            let snapshot = try await accountSnapshot(wallet: wallet, dex: dex, coin: coin)
            try check(wallet: wallet, token: token)
            let book = try HyperliquidOrderBook.decode(await reader.read(.book(coin: coin)), market: snapshot.market, now: clock())
            let nonce = try await journal.nextOrderNonce(wallet: wallet)
            let order = try makeOrder(snapshot, book, nonce)
            let quote = try await quote(order, snapshot: snapshot, wallet: wallet)
            try HyperliquidMarketOrderPlan.checkFunds(quote)
            try check(wallet: wallet, token: token)
            preview = quote
        } catch { if token == revision { errorMessage = message(error) } }
    }

    func confirm(wallet: DeviceWalletSummary) async {
        guard !activeOperation, let reviewed = preview else { return }
        activeOperation = true; isBusy = true; errorMessage = nil
        let token = revision, id = UUID()
        var didReserve = false
        defer { lease?.invalidate(); lease = nil; activeOperation = false; isBusy = false }
        do {
            try await verify(wallet: wallet, token: token)
            // Keep the reviewed intent; refreshing must never silently change size, direction or limit.
            let fresh = try await refresh(reviewed, wallet: wallet)
            try check(wallet: wallet, token: token)
            _ = try await journal.reserveOrder(id: id, preview: fresh, wallet: wallet, continuousNow: continuousClock())
            didReserve = true; preview = nil
            let scope = try service.fundingSigningLease(wallet: wallet)
            lease = scope
            try check(wallet: wallet, token: token)
            let signing = try await journal.beginOrderSigning(id: id, preview: fresh, wallet: wallet, continuousNow: continuousClock())
            let signature = try await signer.signOrder(signing, lease: scope)
            // A created signature must be recorded even after UI cancellation or account changes.
            _ = try await journal.recordOrderSignature(id: id, signature: signature, wallet: wallet)
            try await verify(wallet: wallet, token: token)
            let submissionQuote = try await refresh(reviewed, wallet: wallet)
            try check(wallet: wallet, token: token)
            try scope.check(wallet: wallet)
            let permit = try await journal.beginOrderSubmission(id: id, preview: submissionQuote, wallet: wallet,
                                                                 continuousClock: continuousClock)
            let response: Data?
            do { response = try await broadcaster.submit(permit, lease: scope) }
            catch { response = nil }
            let recorded = try await journal.recordOrderResponse(id: id, response: response, wallet: wallet)
            scope.invalidate(); lease = nil
            if token == revision { result = recorded }
        } catch {
            if token == revision {
                errorMessage = didReserve ? HyperliquidLiveOrderError.recoveryRequired.localizedDescription : message(error)
            }
        }
    }

    private func readFills(_ record: HyperliquidOrderRecord, wallet: DeviceWalletSummary) async throws {
        guard record.fillOrderID != nil else { throw HyperliquidLiveOrderError.recoveryRequired }
        let start = record.order.nonce >= 2000 ? record.order.nonce - 2000 : 0
        let response = try await reader.read(.fills(owner: wallet.address, start: start, end: record.order.expiresAfter + 2000))
        // Retain observed evidence even if the user leaves during this read. Never submit again.
        try await journal.recordOrderFills(id: record.id, response: response, wallet: wallet)
    }

    private func refresh(_ reviewed: HyperliquidOrderPreview, wallet: DeviceWalletSummary) async throws -> HyperliquidOrderPreview {
        let snapshot = try await accountSnapshot(wallet: wallet, dex: reviewed.order.market.dex, coin: reviewed.order.market.coin)
        guard !reviewed.order.reduceOnly || snapshot.position == reviewed.account.position else {
            throw HyperliquidLiveOrderError.changed
        }
        let fresh = try await quote(reviewed.order, snapshot: snapshot, wallet: wallet,
                                    leverage: reviewed.reviewedLeverage, mode: reviewed.reviewedMarginMode)
        try HyperliquidMarketOrderPlan.checkFunds(fresh)
        guard fresh.quote.takerRate <= reviewed.quote.takerRate else { throw HyperliquidLiveOrderError.changed }
        return fresh
    }

    private func accountSnapshot(wallet: DeviceWalletSummary, dex: String, coin: String) async throws -> HyperliquidTradingSnapshot {
        try await HyperliquidTradingSnapshotProvider(reader: reader, clock: clock, continuousClock: continuousClock)
            .snapshot(wallet: wallet, dex: dex, coin: coin)
    }

    private func quote(_ order: HyperliquidOrderIntent, snapshot: HyperliquidTradingSnapshot, wallet: DeviceWalletSummary,
                       leverage: Int? = nil, mode: HyperliquidMarketLeverage.Mode? = nil) async throws -> HyperliquidOrderPreview {
        try await HyperliquidOrderPreviewProvider(reader: reader, clock: clock, continuousClock: continuousClock)
            .preview(order: order, wallet: wallet, account: snapshot, reviewedLeverage: leverage ?? snapshot.active.leverage.multiplier,
                     reviewedMarginMode: mode ?? snapshot.active.leverage.mode)
    }

    private func verify(wallet: DeviceWalletSummary, token: UUID) async throws {
        try check(wallet: wallet, token: token)
        let registration = try await service.walletRegistration()
        try check(wallet: wallet, token: token)
        guard registration.accountId == wallet.accountID, registration.address == wallet.address else { throw DeviceWalletError.accountChanged }
    }

    private func check(wallet: DeviceWalletSummary, token: UUID) throws {
        try Task.checkCancellation()
        guard enabled() else { throw HyperliquidLiveOrderError.unavailable }
        guard token == revision, wallet.canAuthorizeTransactions, service.walletAccountID == wallet.accountID else {
            throw DeviceWalletError.accountChanged
        }
    }

    private func message(_ error: Error) -> String {
        if let error = error as? HyperliquidLiveOrderError { return error.localizedDescription }
        if let error = error as? DeviceWalletError { return error.localizedDescription }
        return HyperliquidLiveOrderError.changed.localizedDescription
    }
}
