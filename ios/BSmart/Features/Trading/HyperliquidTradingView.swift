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
    private let initialCoin: String?
    private let initialAmount: String
    private let initialReduction: Bool
    private let onClose: (() -> Void)?

    @State private var showsMarketPicker = false
    @State private var marketLoadAttempt = 0

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
        initialCoin: String? = nil, initialAmount: String = "", initialReduction: Bool = false,
        onClose: (() -> Void)? = nil
    ) {
        self.symbol = symbol.uppercased()
        self.initialSide = initialSide
        self.presentation = presentation
        self.activities = activities
        self.initialCoin = initialCoin; self.initialAmount = initialAmount; self.initialReduction = initialReduction
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let market = trading.activeMarket {
                if presentation == .quick {
                    marketIdentity(market)
                    LiveMarketOrderDestination(coin: market.coin, dex: market.dex,
                                               side: initialSide == .long ? .buy : .sell,
                                               initialAmount: initialAmount, initialReduction: initialReduction, market: market,
                                               opinionSource: opinionSource?.matches(symbol: market.symbol) == true ? opinionSource : nil)
                        .id(market.coin)
                } else {
                    HyperliquidMarketChart(market: market, activities: activities)
                }
            } else if trading.isLoadingMarket || trading.errorMessage == nil {
                HyperliquidTradeLoadingView(symbol: symbol, presentation: presentation,
                                            reducing: initialReduction, chartRange: trading.chartRange,
                                            isCrypto: initialCoin.map { !$0.contains(":") } ?? false)
                    .transition(.opacity)
            } else if trading.verifiedNoMarketSymbol == symbol && !initialReduction
                        && !ExternalTradeLinks.destinations(for: symbol).isEmpty {
                if presentation == .quick {
                    ScrollView {
                        externalVenuesContent.padding(.top, 40)
                    }
                    .scrollIndicators(.hidden)
                } else {
                    externalVenuesContent.padding(.top, 16)
                }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.largeTitle)
                    Text(trading.errorMessage ?? "Hyperliquid market unavailable".bSmartLocalized)
                        .multilineTextAlignment(.center)
                    Button("Retry".bSmartLocalized) { marketLoadAttempt += 1 }
                        .accessibilityIdentifier("trade.market.retry")
                    if !initialReduction {
                        Button("Choose a market".bSmartLocalized) { showsMarketPicker = true }
                    }
                }
                .foregroundStyle(BSmartColor.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 260)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: presentation == .quick ? .infinity : nil, alignment: .topLeading)
        .animation(.easeOut(duration: 0.2), value: trading.activeMarket?.coin)
        .task(id: "\(symbol):\(marketLoadAttempt)") {
            await trading.runLiveMarket(symbol: symbol, coin: initialCoin)
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

    private var externalVenuesContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            ExternalTradingVenuesView(symbol: symbol)
            Button("Choose a market".bSmartLocalized) { showsMarketPicker = true }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BSmartColor.brand)
        }
    }

    private func marketIdentity(_ market: HyperliquidPerpMarket) -> some View {
        HStack(spacing: 12) {
            BSmartAssetMark(ticker: market.symbol, size: 44, isCrypto: market.dex.isEmpty)
            Button {
                showsMarketPicker = true
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(market.symbol)
                            .font(.system(size: 17, weight: .semibold))
                        if !initialReduction {
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.bold))
                        }
                    }
                    Text("\((market.openInterest * market.markPrice).bSmartCompactUSD) OI")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(BSmartColor.secondaryText)
                }
                .foregroundStyle(BSmartColor.primaryText)
            }
            .buttonStyle(.plain)
            .disabled(initialReduction)
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
            List {
                if trading.isLoadingCatalog && trading.marketCatalog.isEmpty {
                    ForEach(0..<8, id: \.self) { _ in
                        BSmartSkeletonRows(style: .simple, count: 1)
                            .listRowBackground(BSmartColor.ink)
                    }
                } else {
                    ForEach(filteredMarkets) { market in
                        Button {
                            Task {
                                await trading.selectMarket(market)
                                dismiss()
                            }
                        } label: {
                            HStack(spacing: BSmartSpacing.medium) {
                                BSmartAssetMark(ticker: market.symbol, size: 36, isCrypto: market.dex.isEmpty)
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
                }
            }
            .scrollContentBackground(.hidden)
            .background(BSmartColor.ink)
            .searchable(text: $query, prompt: "Market or symbol".bSmartLocalized)
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
