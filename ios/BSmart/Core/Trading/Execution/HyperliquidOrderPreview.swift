import Foundation

// Read-only estimates; no journal, device key or exchange submission authority.
struct HyperliquidOrderPreview: Sendable {
    let order: HyperliquidOrderIntent
    let account: HyperliquidTradingSnapshot
    let quote: HyperliquidDepthQuote
    let builderApproval: HyperliquidBuilderApproval?
    let reviewedLeverage: Int
    let reviewedMarginMode: HyperliquidMarketLeverage.Mode
    let bookUpdatedAt: Date
    let bookRequestedAt: Date
    let bookRequestedContinuousAt: ContinuousClock.Instant
    let checkedAt: Date
    let checkedContinuousAt: ContinuousClock.Instant
    var expiresAt: Date {
        min(Date(timeIntervalSince1970: Double(order.expiresAfter) / 1_000),
            min(account.expiresAt, min(bookUpdatedAt, bookRequestedAt).addingTimeInterval(5)))
    }

    func validate(wallet: DeviceWalletSummary, now: Date, continuousNow: ContinuousClock.Instant = .now) throws {
        if let fee = order.builderFee {
            guard let builderApproval else { throw HyperliquidQuoteError.builderApprovalRequired }
            try builderApproval.validate(owner: order.owner, fee: fee)
        }
        try account.checkConstraints(order: order, wallet: wallet, reviewedLeverage: reviewedLeverage,
                                     reviewedMarginMode: reviewedMarginMode, now: now, continuousNow: continuousNow)
        // Charge network time too; a frozen wall clock must not extend an older book.
        let remaining = expiresAt.timeIntervalSince(bookRequestedAt)
        guard now.timeIntervalSince1970.isFinite, bookRequestedAt <= checkedAt, checkedAt <= now, now < expiresAt,
              remaining.isFinite, remaining > 0, checkedContinuousAt <= continuousNow,
              bookRequestedContinuousAt <= checkedContinuousAt,
              bookRequestedContinuousAt.duration(to: continuousNow) < .seconds(remaining) else { throw HyperliquidQuoteError.stale }
    }
}

struct HyperliquidOrderPreviewProvider: Sendable {
    let reader: any HyperliquidExecutionReading
    let clock: @Sendable () -> Date
    let continuousClock: @Sendable () -> ContinuousClock.Instant

    init(reader: any HyperliquidExecutionReading = HyperliquidExecutionReader(),
         clock: @escaping @Sendable () -> Date = { Date() },
         continuousClock: @escaping @Sendable () -> ContinuousClock.Instant = { .now }) {
        self.reader = reader; self.clock = clock; self.continuousClock = continuousClock
    }

    func preview(order: HyperliquidOrderIntent, wallet: DeviceWalletSummary, account: HyperliquidTradingSnapshot,
                 reviewedLeverage: Int, reviewedMarginMode: HyperliquidMarketLeverage.Mode) async throws -> HyperliquidOrderPreview {
        func validate() throws {
            try Task.checkCancellation()
            try account.checkConstraints(order: order, wallet: wallet, reviewedLeverage: reviewedLeverage,
                reviewedMarginMode: reviewedMarginMode, now: clock(), continuousNow: continuousClock())
        }
        try validate()
        guard order.market.feeContext != nil else { throw HyperliquidQuoteError.feesUnavailable }
        let fees = try HyperliquidTakerFees.decode(await reader.read(.fees(owner: order.owner)), owner: order.owner)
        try validate()
        let approval: HyperliquidBuilderApproval?
        if let fee = order.builderFee {
            approval = try HyperliquidBuilderApproval.decode(await reader.read(.builderApproval(owner: order.owner, builder: fee.address)),
                                                             owner: order.owner, fee: fee)
            try validate()
        } else { approval = nil }
        let bookRequestedAt = clock(), bookRequestedContinuousAt = continuousClock()
        let book = try HyperliquidOrderBook.decode(await reader.read(.book(coin: order.market.coin)), market: order.market, now: clock())
        try validate()
        let quote = try HyperliquidDepthQuote.calculate(order: order, book: book, fees: fees, now: clock())
        let result = HyperliquidOrderPreview(order: order, account: account, quote: quote, builderApproval: approval,
            reviewedLeverage: reviewedLeverage, reviewedMarginMode: reviewedMarginMode, bookUpdatedAt: book.updatedAt,
            bookRequestedAt: bookRequestedAt, bookRequestedContinuousAt: bookRequestedContinuousAt,
            checkedAt: clock(), checkedContinuousAt: continuousClock())
        try result.validate(wallet: wallet, now: clock(), continuousNow: continuousClock())
        try Task.checkCancellation()
        return result
    }
}
