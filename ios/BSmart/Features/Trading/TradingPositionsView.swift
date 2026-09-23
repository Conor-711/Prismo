import SwiftUI

struct TradingPositionsView: View {
    let wallet: DeviceWalletSummary
    var title = "Open positions"
    var profileStyle = false
    var symbol: String? = nil
    @EnvironmentObject private var account: AccountAccessStore
    @State private var store: TradingPositionsStore?

    var body: some View {
        Group {
            if let store { TradingPositionsContent(wallet: wallet, title: title, profileStyle: profileStyle, symbol: symbol, store: store) }
            else { BSmartSkeletonRows(style: .simple, count: 2) }
        }
        .task {
            if store == nil { store = TradingPositionsStore(service: account) }
        }
    }
}

private struct TradingPositionsContent: View {
    let wallet: DeviceWalletSummary
    let title: String
    let profileStyle: Bool
    let symbol: String?
    @ObservedObject var store: TradingPositionsStore
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var trading: HyperliquidTradingStore
    @EnvironmentObject private var model: AppModel
    @State private var selectedPosition: TradingPositionRow?
    @State private var isReducing = true
    @State private var positionQuotes: [String: HyperliquidPerpMarket] = [:]

    private var positions: [TradingPositionRow] {
        store.rows.filter { $0.matches(symbol: symbol) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title.bSmartLocalized).font(.headline)
                Spacer()
                Button { Task { await store.refresh(wallet: wallet) } } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
                }.disabled(store.isLoading).accessibilityLabel("Refresh".bSmartLocalized)
            }
            if store.isLoading && !store.didLoad { BSmartSkeletonRows(style: .simple, count: 2) }
            if let error = store.errorMessage { Text(error).font(.subheadline).foregroundStyle(BSmartColor.bear) }
            if store.didLoad, positions.isEmpty, store.errorMessage == nil {
                Text("No open positions".bSmartLocalized).font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
            }
            if profileStyle && !positions.isEmpty { PortfolioCompactHoldingHeader() }
            ForEach(positions) { position in
                VStack(alignment: .leading, spacing: 12) {
                    if profileStyle {
                        BSmartDetailNavigationLink(id: "portfolio-position-\(position.coin)") {
                            TickerDestinationView(symbol: position.symbol)
                        } label: {
                            PortfolioCompactHoldingRow(
                                holding: .init(live: position,
                                               quote: positionQuotes[position.coin].flatMap {
                                                   PortfolioPositionQuote(position: position, market: $0)
                                               }),
                                companyName: companyName(for: position.symbol),
                                isCrypto: !position.coin.contains(":"))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("portfolio.position.ticker.\(position.symbol)")
                    } else {
                        positionSummary(position)
                        HStack {
                            Text(position.quantity.magnitude.wire + " · " + (position.entryPrice?.wire ?? "--"))
                                .font(.caption.monospacedDigit()).foregroundStyle(BSmartColor.secondaryText)
                            Spacer()
                            Button { isReducing = false; selectedPosition = position } label: {
                                Image(systemName: "plus.circle").frame(width: 44, height: 44)
                            }.accessibilityLabel("Increase position".bSmartLocalized)
                                .accessibilityIdentifier("wallet.position.increase.\(position.coin)")
                            Button { isReducing = true; selectedPosition = position } label: {
                                Label("Reduce / Close".bSmartLocalized, systemImage: "minus.circle")
                                    .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                            }.accessibilityIdentifier("wallet.position.close.\(position.coin)")
                        }
                    }
                    Divider()
                }
            }
        }
        .sheet(item: $selectedPosition, onDismiss: { Task { await store.refresh(wallet: wallet) } }) { position in
            BSmartTradeSheet(symbol: position.symbol,
                initialSide: (position.quantity.isNegative == isReducing) ? .long : .short,
                store: trading.makeSession(), coin: position.coin, initialReduction: isReducing) { selectedPosition = nil }
        }
        .task { await store.refresh(wallet: wallet) }
        .onReceive(NotificationCenter.default.publisher(for: .bSmartTradeFilled)) { _ in
            Task { await store.refresh(wallet: wallet) }
        }
        .task(id: store.rows.map(\.coin).joined(separator: "|")) {
            positionQuotes = [:]
            guard profileStyle, !store.rows.isEmpty else { return }
            let quotes = await trading.freshPositionQuotes(coins: store.rows.map(\.coin))
            guard !Task.isCancelled else { return }
            positionQuotes = quotes
        }
        .onDisappear { store.clear(); positionQuotes = [:] }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { store.clear() }
            else if phase == .active { Task { await store.refresh(wallet: wallet) } }
        }
        .accessibilityIdentifier("wallet.positions")
    }

    private func positionSummary(_ position: TradingPositionRow) -> some View {
        HStack(spacing: 10) {
            BSmartAssetMark(ticker: position.symbol, size: profileStyle ? 40 : 32,
                            isCrypto: !position.coin.contains(":"))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(profileStyle ? position.symbol : position.coin)
                        .font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    if profileStyle {
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(BSmartColor.tertiaryText)
                    }
                }
                Text("\((position.quantity.isNegative ? "Short" : "Long").bSmartLocalized) · \(position.leverage)x")
                    .font(.caption).foregroundStyle(position.quantity.isNegative ? BSmartColor.bear : BSmartColor.bull)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text((position.unrealizedPnL.isNegative ? "-" : "+") + position.unrealizedPnL.magnitude.wire + " USDC")
                    .font(.subheadline.monospacedDigit())
                if profileStyle, let percent = position.returnPercent {
                    Text(percent.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always())) + "%")
                        .font(.caption.monospacedDigit())
                }
            }
            .foregroundStyle(position.unrealizedPnL.isNegative ? BSmartColor.bear : BSmartColor.bull)
            .lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }

    private func companyName(for symbol: String) -> String {
        model.tickerCatalog(markets: trading.marketCatalog)
            .first { $0.symbol.caseInsensitiveCompare(symbol) == .orderedSame }?.companyName ?? symbol
    }
}

struct PortfolioPositionQuote {
    let marketValue: Double
    let currentPrice: Double

    init?(position: TradingPositionRow, market: HyperliquidPerpMarket) {
        guard position.coin == market.coin,
              let quantity = Double(position.quantity.magnitude.wire), quantity.isFinite,
              market.markPrice.isFinite, market.markPrice > 0 else { return nil }
        let value = quantity * market.markPrice
        guard value.isFinite else { return nil }
        marketValue = value
        currentPrice = market.markPrice
    }
}
