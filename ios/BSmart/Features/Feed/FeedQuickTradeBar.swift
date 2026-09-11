import SwiftUI

struct FeedQuickTradeBar: View {
    let item: TradeFeedItem
    let onDismiss: () -> Void
    var isDemo = false
    @State private var request: FeedQuickTradeRequest?

    var body: some View {
        HStack(spacing: 5) {
            BSmartDetailNavigationLink(id: "feed.trade.ticker.\(item.id)") {
                TickerDestinationView(symbol: item.opinion.ticker)
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    BSmartAssetMark(ticker: item.opinion.ticker, size: 23)
                    Text(item.opinion.ticker).font(.system(size: 11, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.6)
                }.frame(width: 54, alignment: .leading).frame(minHeight: 48)
            }
            .buttonStyle(.plain).accessibilityIdentifier("feed.trade.ticker.\(item.id.uuidString)")
            ForEach(FeedQuickTradeChoice.choices) { choice in
                let color = choice.side == .short ? BSmartColor.bear : BSmartColor.bull
                Button {
                    guard request == nil else { return }
                    request = .init(item: item, choice: choice)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: choice.side == .short ? "arrow.down.right" : "arrow.up.right")
                            .font(.system(size: 10, weight: .bold))
                        Text("\(choice.dollars)").font(.system(size: 15, weight: .semibold)).monospacedDigit()
                    }
                    .foregroundStyle(BSmartColor.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(color, in: RoundedRectangle(cornerRadius: 9))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(request != nil)
                .accessibilityLabel("%@ %@ $%d".bSmartLocalized(
                    (choice.side == .short ? "Short" : "Long").bSmartLocalized, item.opinion.ticker, choice.dollars))
                .accessibilityIdentifier("feed.quick.\(item.id.uuidString).\(choice.id)")
            }
        }
        .accessibilityElement(children: .contain)
        .sheet(item: $request, onDismiss: onDismiss) { value in
            if isDemo {
                FeedDemoTradePreview(request: value) { request = nil }
            } else {
                NavigationStack {
                    LiveMarketOrderDestination(coin: value.item.marketCoin,
                        dex: value.item.marketCoin.split(separator: ":").count == 2
                            ? String(value.item.marketCoin.split(separator: ":")[0]) : "",
                        side: value.choice.side == .long ? .buy : .sell, initialAmount: String(value.choice.dollars))
                        .padding(24)
                        .navigationTitle(value.item.opinion.ticker)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .topBarTrailing) {
                            Button("Close".bSmartLocalized) { request = nil }.accessibilityIdentifier("feed.live.close")
                        } }
                        .bSmartPage()
                }.presentationDetents([.large])
            }
        }
    }
}
