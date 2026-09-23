import SwiftUI

struct TradingMarketsView: View {
    @EnvironmentObject private var trading: HyperliquidTradingStore
    @State private var search = ""
    @State private var selectedMarket: HyperliquidPerpMarket?

    private var markets: [HyperliquidPerpMarket] {
        trading.marketCatalog.filter {
            search.isEmpty || $0.symbol.localizedCaseInsensitiveContains(search) || $0.coin.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        List {
            if trading.isLoadingCatalog && markets.isEmpty {
                BSmartSkeletonRows(style: .simple, count: 6)
                    .listRowBackground(BSmartColor.ink)
            }
            ForEach(markets) { market in
                Button { selectedMarket = market } label: {
                    HStack(spacing: 12) {
                        BSmartAssetMark(ticker: market.symbol, size: 32, isCrypto: market.dex.isEmpty)
                        Text(market.coin).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(market.markPrice.bSmartMarketPrice).font(.subheadline.monospacedDigit())
                    }.padding(.vertical, 8)
                }.listRowBackground(BSmartColor.surface)
            }
            if !trading.isLoadingCatalog, markets.isEmpty {
                Text((trading.errorMessage ?? "No markets found").bSmartLocalized)
            }
        }
        .sheet(item: $selectedMarket) { market in
            BSmartTradeSheet(symbol: market.symbol, initialSide: .long, store: trading.makeSession(), coin: market.coin) {
                selectedMarket = nil
            }
        }
        .searchable(text: $search, prompt: "Market or symbol".bSmartLocalized)
        .scrollContentBackground(.hidden).background(BSmartColor.ink)
        .navigationTitle("Trade perpetuals".bSmartLocalized).navigationBarTitleDisplayMode(.inline)
        .task { await trading.loadFullCatalog() }
        .refreshable { await trading.loadFullCatalog() }
        .bSmartPage()
    }
}
