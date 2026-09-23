import Foundation
import Combine

@MainActor
final class HyperliquidMarketOrderStore: ObservableObject {
    enum Phase: String {
        case checking = "Checking order"
        case leverage = "Updating leverage"
        case linking = "Linking opinion"
        case signing = "Signing order"
        case rechecking = "Checking latest balance"
        case submitting = "Submitting order"
    }
    @Published private(set) var phase = Phase.checking {
        didSet { timing.mark(phase.rawValue) }
    }
    private let timing = HyperliquidOrderTiming()
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
    @Published private(set) var isComposing = false
    private let service: any AccountWalletServicing
    private let reader: any HyperliquidExecutionReading
    private let journal: FundingTransactionJournal
    private let signer: any HyperliquidDeviceSigning
    private let broadcaster: any HyperliquidOrderBroadcasting
    private let attribution: (any OpinionOrderAttributing)?
    private let leverageSigner: any HyperliquidLeverageSigning
    private let leverageSender: any HyperliquidLeverageBroadcasting
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
         attribution: (any OpinionOrderAttributing)? = nil,
         leverageSigner: any HyperliquidLeverageSigning = KeychainDeviceWalletVault(),
         leverageSender: any HyperliquidLeverageBroadcasting = HyperliquidOrderBroadcaster(),
         clock: @escaping @Sendable () -> Date = { Date() },
         continuousClock: @escaping @Sendable () -> ContinuousClock.Instant = { .now }, enabled: @escaping () -> Bool) {
        self.service = service; self.journal = journal; self.reader = reader; self.signer = signer
        self.broadcaster = broadcaster; self.enabled = enabled; self.clock = clock; self.continuousClock = continuousClock
        self.attribution = attribution
        self.leverageSigner = leverageSigner; self.leverageSender = leverageSender
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
        let orderToken = revision
        entryRevision = request; isLoadingEntry = true; entryError = nil
        defer { if entryRevision == request { isLoadingEntry = false } }
        func validate() throws {
            try Task.checkCancellation()
            guard enabled(), entryRevision == request, wallet.canAuthorizeTransactions,
                  service.walletAccountID == wallet.accountID else { throw DeviceWalletError.accountChanged }
        }
        do {
            try await waitForSession(wallet: wallet, token: orderToken)
            try validate()
            let registration = try await registration(wallet: wallet, token: orderToken)
            try await waitForSession(wallet: wallet, token: orderToken)
            try validate()
            guard registration.accountId == wallet.accountID, registration.address == wallet.address else {
                throw DeviceWalletError.accountChanged
            }
            async let snapshotRequest = accountSnapshot(wallet: wallet, dex: dex, coin: coin)
            async let feeRequest = reader.read(.fees(owner: wallet.address))
            let snapshot = try await snapshotRequest
            let fees = try HyperliquidTakerFees.decode(await feeRequest, owner: wallet.address)
            try await waitForSession(wallet: wallet, token: orderToken)
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

    // Called only by the user's slide confirmation. The draft amount is margin, as in the original composer.
    func executeMargin(_ margin: String, leverage: Int, side: HyperliquidOrderIntent.Side,
                       wallet: DeviceWalletSummary, dex: String, coin: String) async {
        guard !isComposing, !activeOperation, result == nil else { return }
        isComposing = true; errorMessage = nil; result = nil
        timing.begin()
        phase = .checking
        let token = revision
        defer { isComposing = false; timing.end(result == nil ? "stopped" : "exchange_response") }
        do {
            try await waitForSession(wallet: wallet, token: token)
            try check(wallet: wallet, token: token)
            async let authority: Void = verify(wallet: wallet, token: token)
            async let snapshotRequest = accountSnapshot(wallet: wallet, dex: dex, coin: coin)
            async let feeRequest = reader.read(.fees(owner: wallet.address))
            let snapshot = try await snapshotRequest
            try await authority
            try check(wallet: wallet, token: token)
            guard (1...snapshot.market.maximumLeverage).contains(leverage) else { throw HyperliquidExecutionError.invalidIntent }
            let amount = try HyperliquidOrderDecimal(margin)
            guard amount.isPositive, amount.scale <= 6 else { throw HyperliquidLiveOrderError.invalidAmount }
            let notional = try HyperliquidExactValue(amount).multiplied(by: .init(UInt64(leverage))).rounded(decimalPlaces: 6, up: false)
            guard notional >= (try HyperliquidOrderDecimal("10")) else { throw HyperliquidLiveOrderError.invalidAmount }
            let fees = try HyperliquidTakerFees.decode(await feeRequest, owner: wallet.address)
            let fee = try HyperliquidExactValue(notional).multiplied(by: fees.rate(market: snapshot.market))
            let capacity = side == .buy ? snapshot.active.buy : snapshot.active.sell
            guard try HyperliquidExactValue(amount).adding(fee) <= HyperliquidExactValue(capacity.availableToTrade) else {
                throw HyperliquidLiveOrderError.insufficientBalance
            }
            try check(wallet: wallet, token: token)
            var actual = snapshot
            if leverage != snapshot.active.leverage.multiplier {
                phase = .leverage
                guard snapshot.position == nil else { throw HyperliquidTradingCheckError.leverageChanged }
                let permit = try await journal.reserveLeverage(wallet: wallet, market: snapshot.market,
                    leverage: leverage, isCross: snapshot.active.leverage.mode == .cross)
                let scope = try service.fundingSigningLease(wallet: wallet)
                lease = scope
                let signature = try await leverageSigner.signLeverage(permit, lease: scope)
                try await verify(wallet: wallet, token: token)
                let response = try await leverageSender.submit(permit, signature: signature, lease: scope)
                scope.invalidate(); lease = nil
                try check(wallet: wallet, token: token)
                guard let response, let json = try JSONSerialization.jsonObject(with: response) as? [String: Any],
                      json["status"] as? String == "ok" else { throw HyperliquidTradingCheckError.leverageChanged }
                actual = try await accountSnapshot(wallet: wallet, dex: dex, coin: coin)
            }
            try check(wallet: wallet, token: token)
            guard actual.active.leverage.multiplier == leverage else { throw HyperliquidTradingCheckError.leverageChanged }
            entryAccount = actual
            await review(wallet: wallet, dex: dex, coin: coin, preparedSnapshot: actual) { snapshot, book, nonce in
                try HyperliquidMarketOrderPlan.order(notional: notional.wire, side: side, slippageBPS: 50,
                    wallet: wallet, snapshot: snapshot, book: book, nonce: nonce)
            }
            try check(wallet: wallet, token: token)
            if preview != nil { await confirm(wallet: wallet, sameSlide: true) }
        } catch {
            lease?.invalidate(); lease = nil
            if token == revision { errorMessage = message(error) }
        }
    }

    // One explicit slide uses the same review/sign/submit pipeline, with reduceOnly fixed by the plan.
    func executeReduction(percent: Int, wallet: DeviceWalletSummary, dex: String, coin: String) async {
        guard !isComposing, !activeOperation, result == nil else { return }
        isComposing = true
        timing.begin()
        let token = revision
        defer { isComposing = false; timing.end(result == nil ? "stopped" : "exchange_response") }
        await reviewReduction(percent: percent, slippageBPS: 50, wallet: wallet, dex: dex, coin: coin)
        guard token == revision, !Task.isCancelled, preview != nil else { return }
        await confirm(wallet: wallet, sameSlide: true)
    }

    func reviewReduction(percent: Int, slippageBPS: UInt64, wallet: DeviceWalletSummary, dex: String, coin: String) async {
        await review(wallet: wallet, dex: dex, coin: coin) { snapshot, book, nonce in
            try HyperliquidMarketOrderPlan.reduction(percent: percent, slippageBPS: slippageBPS,
                wallet: wallet, snapshot: snapshot, book: book, nonce: nonce)
        }
    }

    private func review(wallet: DeviceWalletSummary, dex: String, coin: String,
                        preparedSnapshot: HyperliquidTradingSnapshot? = nil,
                        makeOrder: (HyperliquidTradingSnapshot, HyperliquidOrderBook, UInt64) throws -> HyperliquidOrderIntent) async {
        guard !activeOperation else { return }
        activeOperation = true; isBusy = true; errorMessage = nil; preview = nil; result = nil
        phase = .checking
        let token = revision
        defer { activeOperation = false; isBusy = false }
        do {
            if preparedSnapshot == nil { try await verify(wallet: wallet, token: token) }
            else { try check(wallet: wallet, token: token) }
            let snapshot: HyperliquidTradingSnapshot
            if let preparedSnapshot {
                try preparedSnapshot.validate(wallet: wallet, now: clock(), continuousNow: continuousClock())
                guard preparedSnapshot.market.dex == dex, preparedSnapshot.market.coin == coin else {
                    throw HyperliquidLiveOrderError.changed
                }
                snapshot = preparedSnapshot
            } else { snapshot = try await accountSnapshot(wallet: wallet, dex: dex, coin: coin) }
            try check(wallet: wallet, token: token)
            let observation = try await HyperliquidBookObservation.read(reader: reader, market: snapshot.market,
                                                                       clock: clock, continuousClock: continuousClock)
            let nonce = try await journal.nextOrderNonce(wallet: wallet)
            let order = try makeOrder(snapshot, observation.book, nonce)
            let quote = try await quote(order, snapshot: snapshot, wallet: wallet, observedBook: observation)
            try HyperliquidMarketOrderPlan.checkFunds(quote)
            try check(wallet: wallet, token: token)
            preview = quote
        } catch { if token == revision { errorMessage = message(error) } }
    }

    func confirm(wallet: DeviceWalletSummary) async {
        await confirm(wallet: wallet, sameSlide: false)
    }

    private func confirm(wallet: DeviceWalletSummary, sameSlide: Bool) async {
        guard !activeOperation, let reviewed = preview else { return }
        if !sameSlide { timing.begin() }
        activeOperation = true; isBusy = true; errorMessage = nil
        let token = revision, id = UUID()
        phase = .checking
        var didReserve = false
        var didAttribute = false
        defer {
            if !sameSlide { timing.end(result == nil ? "stopped" : "exchange_response") }
            lease?.invalidate(); lease = nil; activeOperation = false; isBusy = false
            if didAttribute, let attribution { Task { await attribution.synchronize(order: reviewed.order) } }
        }
        do {
            try check(wallet: wallet, token: token)
            // These are independent read-only checks; signing still awaits every result.
            async let refreshed = signingPreview(reviewed, wallet: wallet, sameSlide: sameSlide)
            async let authority: Void = verify(wallet: wallet, token: token)
            if !reviewed.order.reduceOnly, let attribution {
                phase = .linking
                do { try await attribution.register(order: reviewed.order); didAttribute = true }
                catch {
                    if token == revision {
                        timing.mark("failure.opinion_link." + ((error as? OpinionLinkError)?.rawValue ?? "unavailable"))
                        errorMessage = (error as? OpinionLinkError)?.message
                            ?? ((error as? AccountAccessError) == .expired ? message(error) : OpinionLinkError.unavailable.message)
                        preview = nil
                    }
                    return
                }
            }
            try await authority
            // Keep the reviewed intent; refreshing must never silently change size, direction or limit.
            let fresh: HyperliquidOrderPreview
            do {
                let candidate = try await refreshed
                try candidate.validate(wallet: wallet, now: clock(), continuousNow: continuousClock())
                fresh = candidate
            } catch where sameSlide && HyperliquidOrderFailure.isExpiredObservation(error) {
                // Attribution/authentication may outlive the book. Refresh once before any
                // reservation/signature, preserving the exact attributed intent and constraints.
                timing.mark("pre_sign_quote_refresh")
                fresh = try await refresh(reviewed, wallet: wallet)
            }
            try fresh.validate(wallet: wallet, now: clock(), continuousNow: continuousClock())
            try check(wallet: wallet, token: token)
            _ = try await journal.reserveOrder(id: id, preview: fresh, wallet: wallet, continuousNow: continuousClock())
            didReserve = true; preview = nil
            let scope = try service.fundingSigningLease(wallet: wallet)
            lease = scope
            try check(wallet: wallet, token: token)
            let signing = try await journal.beginOrderSigning(id: id, preview: fresh, wallet: wallet, continuousNow: continuousClock())
            phase = .signing
            let signature = try await signer.signOrder(signing, lease: scope)
            // A created signature must be recorded even after UI cancellation or account changes.
            _ = try await journal.recordOrderSignature(id: id, signature: signature, wallet: wallet)
            phase = .rechecking
            async let submissionAuthority = verify(wallet: wallet, token: token)
            let submissionQuote = try await refresh(reviewed, wallet: wallet)
            try await submissionAuthority
            try check(wallet: wallet, token: token)
            try scope.check(wallet: wallet)
            let permit = try await journal.beginOrderSubmission(id: id, preview: submissionQuote, wallet: wallet,
                                                                 continuousClock: continuousClock)
            let response: Data?
            phase = .submitting
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
        guard snapshot.position == reviewed.account.position,
              snapshot.positions.updatedAt >= reviewed.account.positions.updatedAt else {
            throw HyperliquidLiveOrderError.changed
        }
        let fresh = try await quote(reviewed.order, snapshot: snapshot, wallet: wallet,
                                    leverage: reviewed.reviewedLeverage, mode: reviewed.reviewedMarginMode)
        try HyperliquidMarketOrderPlan.checkFunds(fresh)
        guard fresh.account.mode == reviewed.account.mode else { throw HyperliquidLiveOrderError.changed }
        guard fresh.quote.takerRate <= reviewed.quote.takerRate else { throw HyperliquidLiveOrderError.changed }
        return fresh
    }

    // A slide creates its review immediately, with no intervening user input. Reuse only
    // that operation's unexpired proof; manual review/confirm and post-sign checks refresh.
    private func signingPreview(_ reviewed: HyperliquidOrderPreview, wallet: DeviceWalletSummary,
                                sameSlide: Bool) async throws -> HyperliquidOrderPreview {
        if sameSlide {
            try reviewed.validate(wallet: wallet, now: clock(), continuousNow: continuousClock())
            try HyperliquidMarketOrderPlan.checkFunds(reviewed)
            return reviewed
        }
        return try await refresh(reviewed, wallet: wallet)
    }

    private func accountSnapshot(wallet: DeviceWalletSummary, dex: String, coin: String) async throws -> HyperliquidTradingSnapshot {
        try await timing.measure("account_snapshot") {
            let observation = HyperliquidOrderAccountObservation(reader: reader, clock: clock, continuousClock: continuousClock)
            do {
                return try await observation.snapshot(wallet: wallet, dex: dex, coin: coin)
            } catch let error as HyperliquidTradingCheckError where error == .stale || error == .unavailable {
                // A slow read may exhaust its own freshness window. A new read-only
                // observation is safe before the one-shot exchange submission.
                timing.mark("account_snapshot.retry_read")
                try Task.checkCancellation()
                return try await observation.snapshot(wallet: wallet, dex: dex, coin: coin)
            }
        }
    }

    private func quote(_ order: HyperliquidOrderIntent, snapshot: HyperliquidTradingSnapshot, wallet: DeviceWalletSummary,
                       leverage: Int? = nil, mode: HyperliquidMarketLeverage.Mode? = nil,
                       observedBook: HyperliquidBookObservation? = nil) async throws -> HyperliquidOrderPreview {
        try await HyperliquidOrderPreviewProvider(reader: reader, clock: clock, continuousClock: continuousClock)
            .preview(order: order, wallet: wallet, account: snapshot, reviewedLeverage: leverage ?? snapshot.active.leverage.multiplier,
                     reviewedMarginMode: mode ?? snapshot.active.leverage.mode, observedBook: observedBook)
    }

    private func verify(wallet: DeviceWalletSummary, token: UUID) async throws {
        let registered = try await registration(wallet: wallet, token: token)
        guard registered.accountId == wallet.accountID, registered.address == wallet.address else {
            throw DeviceWalletError.accountChanged
        }
    }

    private func registration(wallet: DeviceWalletSummary, token: UUID) async throws -> TradingWalletRegistration {
        let sessionRevision = service.walletSessionRevision
        for attempt in 0..<2 {
            try await waitForSession(wallet: wallet, token: token, sessionRevision: sessionRevision)
            do {
                let result = try await timing.measure("wallet_registry") { try await service.walletRegistration() }
                try await waitForSession(wallet: wallet, token: token, sessionRevision: sessionRevision)
                return result
            } catch DeviceWalletError.accountChanged where attempt == 0 && service.walletSessionRevision == sessionRevision {
                // Token rotation can finish while the registry request is in flight.
                // A different login changes sessionRevision and must never be retried.
                try await waitForSession(wallet: wallet, token: token, sessionRevision: sessionRevision)
            } catch AccountAccessError.expired where attempt == 0 && service.walletSessionRevision == sessionRevision &&
                (service.walletSessionIsRefreshing || service.walletAccountID == wallet.accountID) {
                // A 401 from a genuinely revoked session clears the account and
                // cannot satisfy this guard; only a same-account refresh retries.
                try await waitForSession(wallet: wallet, token: token, sessionRevision: sessionRevision)
            }
        }
        throw DeviceWalletError.accountChanged
    }

    private func waitForSession(wallet: DeviceWalletSummary, token: UUID,
                                sessionRevision: UUID? = nil) async throws {
        let expected = sessionRevision ?? service.walletSessionRevision
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while service.walletSessionIsRefreshing {
            try Task.checkCancellation()
            guard enabled(), token == revision, wallet.canAuthorizeTransactions,
                  service.walletSessionRevision == expected else { throw DeviceWalletError.accountChanged }
            guard ContinuousClock.now < deadline else { throw HyperliquidTradingCheckError.stale }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard service.walletSessionRevision == expected else { throw DeviceWalletError.accountChanged }
        try check(wallet: wallet, token: token)
    }

    private func check(wallet: DeviceWalletSummary, token: UUID) throws {
        try Task.checkCancellation()
        guard enabled() else { throw HyperliquidLiveOrderError.unavailable }
        if service.walletSessionIsRefreshing { throw HyperliquidTradingCheckError.stale }
        guard token == revision, wallet.canAuthorizeTransactions, service.walletAccountID == wallet.accountID else {
            throw DeviceWalletError.accountChanged
        }
    }

    private func message(_ error: Error) -> String {
        timing.mark("failure." + HyperliquidOrderFailure.code(error))
        if let error = error as? FundingJournalError { return error.orderMessage }
        if let error = error as? EmbeddedWalletError { return error.localizedDescription }
        if let error = error as? AccountAccessError { return error.localizedDescription }
        if let error = error as? HyperliquidLiveOrderError { return error.localizedDescription }
        if let error = error as? DeviceWalletError { return error.localizedDescription }
        return HyperliquidOrderFailure.message(error)
    }

}
