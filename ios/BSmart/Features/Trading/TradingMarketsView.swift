import SwiftUI

struct TradingMarketsView: View {
    @EnvironmentObject private var trading: HyperliquidTradingStore
    @State private var search = ""

    private var markets: [HyperliquidPerpMarket] {
        trading.marketCatalog.filter {
            search.isEmpty || $0.symbol.localizedCaseInsensitiveContains(search) || $0.coin.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        List {
            if trading.isLoadingCatalog && markets.isEmpty { ProgressView() }
            ForEach(markets) { market in
                NavigationLink {
                    LiveMarketOrderDestination(coin: market.coin, dex: market.dex, side: .buy, market: market)
                        .padding(.horizontal, 20).navigationTitle(market.coin).navigationBarTitleDisplayMode(.inline)
                } label: {
                    HStack(spacing: 12) {
                        BSmartAssetMark(ticker: market.symbol, size: 32)
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
        .searchable(text: $search, prompt: "Market or symbol".bSmartLocalized)
        .scrollContentBackground(.hidden).background(BSmartColor.ink)
        .navigationTitle("Trade perpetuals".bSmartLocalized).navigationBarTitleDisplayMode(.inline)
        .task { await trading.loadFullCatalog() }
        .refreshable { await trading.loadFullCatalog() }
        .bSmartPage()
    }
}
