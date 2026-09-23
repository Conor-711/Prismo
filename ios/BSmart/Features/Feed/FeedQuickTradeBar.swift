import SwiftUI

struct FeedQuickTradeBar: View {
    @EnvironmentObject private var trading: HyperliquidTradingStore
    let item: TradeFeedItem
    let onDismiss: () -> Void
    var isDemo = false
    @State private var request: TradeRequest?

    private struct TradeRequest: Identifiable {
        let id = UUID()
    }

    var body: some View {
        Button {
            guard request == nil else { return }
            request = TradeRequest()
        } label: {
            Label("Trade".bSmartLocalized, systemImage: "arrow.left.arrow.right")
                .font(.system(size: 15, weight: .semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(BSmartColor.onAccent)
                .padding(.horizontal, 16)
                .frame(minWidth: 112, minHeight: 44)
                .background(BSmartColor.brand, in: RoundedRectangle(cornerRadius: 8))
                .shadow(color: BSmartColor.brand.opacity(0.2), radius: 8, y: 3)
                .contentShape(Rectangle())
        }
        .buttonStyle(FeedTradeActionStyle())
        .disabled(request != nil)
        .accessibilityLabel("%@ %@".bSmartLocalized("Trade".bSmartLocalized, item.opinion.ticker))
        .accessibilityIdentifier("feed.quick.\(item.id.uuidString).trade")
        .sheet(item: $request, onDismiss: onDismiss) { _ in
            if isDemo {
                FeedDemoTradePreview(item: item, side: item.side) { request = nil }
            } else {
                BSmartTradeSheet(symbol: item.opinion.ticker, initialSide: item.side,
                    store: trading.makeSession(), coin: item.marketCoin) {
                    request = nil
                }.environment(\.opinionTradeSource, item.source)
            }
        }
    }
}

private struct FeedTradeActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
