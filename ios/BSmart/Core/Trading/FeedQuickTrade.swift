import Foundation

struct FeedQuickTradeChoice: Identifiable, Equatable {
    let side: PaperTradeSide
    let dollars: Int
    var id: String { "\(side.rawValue).\(dollars)" }
    static let choices: [Self] = [
        .init(side: .short, dollars: 100), .init(side: .short, dollars: 500),
        .init(side: .long, dollars: 500), .init(side: .long, dollars: 100)
    ]
}

struct FeedQuickTradeRequest: Identifiable {
    let id = UUID()
    let item: TradeFeedItem
    let choice: FeedQuickTradeChoice
}

@MainActor
final class FeedQuickTradeExecutor: ObservableObject {
    @Published private(set) var execution: PaperTradeExecution?
    @Published private(set) var errorMessage: String?
    @Published private(set) var loading = false
    private var started = false
    private var cancelled = false

    func cancel() { cancelled = true; loading = false }

    func execute(_ request: FeedQuickTradeRequest, paper: PaperTradingEngine,
                 quote: () async throws -> HyperliquidPerpMarket) async {
        // One executor instance per explicit tap. No auto retry after cancellation/failure.
        guard !started, !cancelled else { return }
        started = true
        loading = true
        defer { loading = false }
        do {
            guard FeedQuickTradeChoice.choices.contains(request.choice) else { throw PaperTradingError.invalidAmount }
            let market = try await quote()
            try Task.checkCancellation()
            guard !cancelled else { return }
            guard market.coin == request.item.marketCoin,
                  market.symbol.caseInsensitiveCompare(request.item.opinion.ticker) == .orderedSame,
                  request.item.source.matches(symbol: market.symbol),
                  !market.isDelisted, TradeAmountInput.quoteIsCurrent(market.updatedAt) else {
                throw PaperTradingError.invalidPrice
            }
            let existing = paper.account.positions.first { $0.coin == market.coin }
            let leverage = existing?.leverage ?? 1
            let margin = Double(request.choice.dollars) / Double(leverage)
            // Source stays attached to the request, but paper orders NEVER enter the verified Feed.
            execution = try paper.placeMarketOrder(side: request.choice.side, margin: margin,
                                                   leverage: leverage, market: market)
        } catch {
            if !cancelled && !Task.isCancelled { errorMessage = error.localizedDescription }
        }
    }
}
