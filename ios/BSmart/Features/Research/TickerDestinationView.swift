import SwiftUI

struct TickerDestinationView: View {
    @EnvironmentObject private var trading: HyperliquidTradingStore
    let symbol: String

    var body: some View {
        TickerDestinationContent(symbol: symbol.uppercased(), store: trading.makeSession())
    }
}

private struct TickerDestinationContent: View {
    @StateObject private var store: HyperliquidTradingStore
    let symbol: String

    init(symbol: String, store: HyperliquidTradingStore) {
        self.symbol = symbol
        _store = StateObject(wrappedValue: store)
    }

    var body: some View {
        TickerIntelligenceView(symbol: symbol)
        .environmentObject(store)
        .toolbar(.visible, for: .navigationBar)
    }
}

private struct TickerLogoDestinationModifier: ViewModifier {
    let symbol: String
    @State private var isPresented = false
    @Namespace private var transition

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .highPriorityGesture(TapGesture().onEnded { isPresented = true })
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(symbol)
            .accessibilityIdentifier("ticker.logo.\(symbol.uppercased())")
            .accessibilityAction { isPresented = true }
            .bSmartMatchedTransitionSource(id: symbol, in: transition)
            .fullScreenCover(isPresented: $isPresented) {
                NavigationStack {
                    TickerDestinationView(symbol: symbol)
                }
                .bSmartZoomNavigationTransition(sourceID: symbol, in: transition)
            }
    }
}

extension View {
    func bSmartTickerDestination(_ symbol: String) -> some View {
        modifier(TickerLogoDestinationModifier(symbol: symbol))
    }
}
