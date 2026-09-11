import Charts
import SwiftUI

enum HyperliquidTradingPresentation {
    case full
    case quick
}

struct HyperliquidTradingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.opinionTradeSource) private var opinionSource
    @EnvironmentObject private var trading: HyperliquidTradingStore
    let symbol: String
    let initialSide: PaperTradeSide
    let presentation: HyperliquidTradingPresentation
    var activities: [TickerSmartActivityItem]? = nil
    private let onClose: (() -> Void)?

    @State private var showsMarketPicker = false

    init(
        ticker: TickerIntelligence,
        initialSide: PaperTradeSide = .long,
        presentation: HyperliquidTradingPresentation = .full
    ) {
        self.init(symbol: ticker.ticker, initialSide: initialSide, presentation: presentation)
    }

    init(
        symbol: String,
        initialSide: PaperTradeSide = .long,
        presentation: HyperliquidTradingPresentation = .full,
        activities: [TickerSmartActivityItem]? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.symbol = symbol.uppercased()
        self.initialSide = initialSide
        self.presentation = presentation
        self.activities = activities
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let market = trading.activeMarket {
                if presentation == .quick {
                    marketIdentity(market)
                    LiveMarketOrderDestination(coin: market.coin, dex: market.dex,
                                               side: initialSide == .long ? .buy : .sell, market: market)
                        .id(market.coin)
                } else {
                    HyperliquidMarketChart(market: market, activities: activities)
                }
            } else if trading.isLoadingMarket {
                ProgressView("Loading Hyperliquid market".bSmartLocalized)
                    .tint(BSmartColor.brand)
                    .frame(maxWidth: .infinity, minHeight: 320)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.largeTitle)
                    Text(trading.errorMessage ?? "Hyperliquid market unavailable".bSmartLocalized)
                        .multilineTextAlignment(.center)
                    Button("Choose a market".bSmartLocalized) { showsMarketPicker = true }
                }
                .foregroundStyle(BSmartColor.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 260)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: presentation == .quick ? .infinity : nil, alignment: .topLeading)
        .task(id: symbol) {
            await trading.runLiveMarket(symbol: symbol)
        }
        .task(id: trading.chartRange) {
            await trading.reloadCandles()
        }
        .sheet(isPresented: $showsMarketPicker) {
            HyperliquidMarketPickerView()
                .environmentObject(trading)
        }
    }

    private func closeTrading() {
        if let onClose { onClose() } else { dismiss() }
    }

    private func marketIdentity(_ market: HyperliquidPerpMarket) -> some View {
        HStack(spacing: 12) {
            BSmartAssetMark(ticker: market.symbol, size: 44)
            Button {
                showsMarketPicker = true
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(market.symbol)
                            .font(.system(size: 17, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.bold))
                    }
                    Text("\((market.openInterest * market.markPrice).bSmartCompactUSD) OI")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(BSmartColor.secondaryText)
                }
                .foregroundStyle(BSmartColor.primaryText)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("trade.market-picker")
            Spacer(minLength: 8)
            if presentation == .quick {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(market.markPrice.bSmartMarketPrice)
                        .font(.headline).monospacedDigit()
                    Text("Market order".bSmartLocalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BSmartColor.secondaryText)
                }
                Button(action: closeTrading) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 32, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(BSmartColor.secondaryText)
                .accessibilityLabel("Close".bSmartLocalized)
                .accessibilityIdentifier("trade.close")
            }
        }
    }
}


struct HyperliquidMarketPickerView: View {
    @EnvironmentObject private var trading: HyperliquidTradingStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filteredMarkets: [HyperliquidPerpMarket] {
        guard !query.isEmpty else { return trading.marketCatalog }
        return trading.marketCatalog.filter {
            $0.symbol.localizedCaseInsensitiveContains(query)
                || $0.coin.localizedCaseInsensitiveContains(query)
                || $0.dexDisplayName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if trading.isLoadingCatalog && trading.marketCatalog.isEmpty {
                    ProgressView("Loading Hyperliquid markets".bSmartLocalized)
                        .tint(BSmartColor.brand)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filteredMarkets) { market in
                        Button {
                            Task {
                                await trading.selectMarket(market)
                                dismiss()
                            }
                        } label: {
                            HStack(spacing: BSmartSpacing.medium) {
                                BSmartAssetMark(ticker: market.symbol, size: 36)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(market.symbol)
                                        .font(.subheadline.weight(.black))
                                        .foregroundStyle(BSmartColor.primaryText)
                                    Text("\(market.maxLeverage)x")
                                        .font(.caption2)
                                        .foregroundStyle(BSmartColor.tertiaryText)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text(market.markPrice.bSmartMarketPrice)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(BSmartColor.primaryText)
                                        .monospacedDigit()
                                    Text(market.dayChangePercent.formatted(
                                        .percent.precision(.fractionLength(2)).sign(strategy: .always())
                                    ))
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(market.dayChangePercent >= 0 ? BSmartColor.bull : BSmartColor.bear)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(BSmartColor.surface)
                    }
                    .scrollContentBackground(.hidden)
                    .background(BSmartColor.ink)
                    .searchable(text: $query, prompt: "Market or symbol".bSmartLocalized)
                }
            }
            .navigationTitle("Hyperliquid markets".bSmartLocalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done".bSmartLocalized) { dismiss() }
                }
            }
            .task {
                await trading.loadFullCatalog()
            }
        }
        .bSmartPage()
    }
}
