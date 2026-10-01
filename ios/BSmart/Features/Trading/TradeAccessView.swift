import SwiftUI

private struct OpinionTradeSourceKey: EnvironmentKey {
    static let defaultValue: OpinionTradeSource? = nil
}

extension EnvironmentValues {
    var opinionTradeSource: OpinionTradeSource? {
        get { self[OpinionTradeSourceKey.self] }
        set { self[OpinionTradeSourceKey.self] = newValue }
    }
}

enum BSmartTradeButtonStyle {
    case compact
    case mirror
    case prominent
    case side
}

struct BSmartTradeButton: View {
    @EnvironmentObject private var trading: HyperliquidTradingStore
    let symbol: String
    var style: BSmartTradeButtonStyle = .compact
    var initialSide: PaperTradeSide = .long
    var opinionSource: OpinionTradeSource? = nil
    var marketCoin: String? = nil
    var onTradeDismiss: (() -> Void)? = nil

    @State private var showsTrading = false

    private var accent: Color {
        initialSide == .long ? BSmartColor.bull : BSmartColor.bear
    }

    private var title: String {
        if style == .mirror { return "Mirror".bSmartLocalized }
        if style != .compact {
            return (initialSide == .long ? "Long" : "Short").bSmartLocalized
        }
        return "Trade".bSmartLocalized
    }

    private var accessibilityIdentifier: String {
        let base = "trade.open.\(symbol.lowercased())"
        return initialSide == .long ? base : "\(base).short"
    }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showsTrading = true
        } label: {
            HStack(spacing: style == .side ? 5 : 8) {
                if style == .compact || style == .mirror {
                    Image(systemName: style == .mirror ? "square.on.square" : "arrow.up.arrow.down")
                        .font(.system(size: style == .mirror ? 13 : 11, weight: .bold))
                        .foregroundStyle(style == .mirror ? BSmartColor.brand : accent)
                }
                Text(title)
                    .font(.system(size: style == .compact ? 11 : style == .mirror ? 14 : 15,
                                  weight: style == .mirror ? .bold : .semibold))
            }
            .foregroundStyle(style == .compact ? accent : style == .mirror
                             ? BSmartColor.primaryText : BSmartColor.onAccent)
            .padding(.horizontal, style == .mirror ? 14 : style == .compact ? 12 : 14)
            .frame(maxWidth: style == .prominent || style == .mirror ? .infinity : nil)
            .frame(height: style == .compact ? 32 : style == .mirror ? 40 : 44)
            .background {
                if style == .compact {
                    Capsule().fill(accent.opacity(0.11))
                } else {
                    RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous)
                        .fill(style == .mirror ? BSmartColor.ink.opacity(0.55) : accent)
                }
            }
            .overlay {
                if style == .compact {
                    Capsule().stroke(accent.opacity(0.7), lineWidth: 0.8)
                } else {
                    RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous)
                        .strokeBorder(style == .mirror ? BSmartColor.brand.opacity(0.35)
                                      : BSmartColor.controlOutline, lineWidth: 0.8)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(BSmartTradePressStyle())
        .accessibilityLabel("%@ %@".bSmartLocalized(title, symbol.uppercased()))
        .accessibilityIdentifier(accessibilityIdentifier)
        .sheet(isPresented: $showsTrading, onDismiss: { onTradeDismiss?() }) {
            BSmartTradeSheet(symbol: symbol, initialSide: initialSide, store: trading.makeSession(), coin: marketCoin) {
                showsTrading = false
            }
            .environment(\.opinionTradeSource, opinionSource?.matches(symbol: symbol) == true ? opinionSource : nil)
        }
    }
}

private struct BSmartTradePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct BSmartTradeCardBar: View {
    let symbol: String
    var width: CGFloat? = nil

    var body: some View {
        HStack(spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(BSmartColor.gold)
                Text("Trade %@".bSmartLocalized(symbol.uppercased()))
                    .font(.system(size: 10, weight: .black))
                    .tracking(0.25)
                    .foregroundStyle(BSmartColor.tradeBarText)
                    .lineLimit(1)
            }

            Spacer(minLength: 2)

            BSmartTradeButton(symbol: symbol, style: .side, initialSide: .long)
            BSmartTradeButton(symbol: symbol, style: .side, initialSide: .short)
        }
        .padding(.horizontal, 12)
        .frame(width: width, height: 52)
        .background(BSmartColor.tradeBarSurface)
        .overlay(alignment: .top) {
            Rectangle().fill(BSmartColor.tradeBarLine).frame(height: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trade.card.\(symbol.lowercased())")
    }
}

struct BSmartTradeDock: View {
    @EnvironmentObject private var trading: HyperliquidTradingStore
    let symbol: String
    var opinionSource: OpinionTradeSource? = nil
    var marketCoin: String? = nil
    var onTradeDismiss: (() -> Void)? = nil
    @State private var showsExternalVenues = false

    var body: some View {
        Group {
            if marketCoin == nil, trading.verifiedNoMarketSymbol == symbol.uppercased(),
               !ExternalTradeLinks.destinations(for: symbol).isEmpty {
                Button { showsExternalVenues = true } label: {
                    HStack {
                        Text("View on another platform".bSmartLocalized)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BSmartColor.onAccent)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(BSmartColor.brand, in: RoundedRectangle(cornerRadius: BSmartRadius.control))
                }
                .buttonStyle(.bSmartPlain)
                .accessibilityIdentifier("trade.external.open")
            } else {
                HStack(spacing: 10) {
                    BSmartTradeButton(symbol: symbol, style: .prominent, initialSide: .short, opinionSource: opinionSource, marketCoin: marketCoin, onTradeDismiss: onTradeDismiss)
                    BSmartTradeButton(symbol: symbol, style: .prominent, initialSide: .long, opinionSource: opinionSource, marketCoin: marketCoin, onTradeDismiss: onTradeDismiss)
                }
            }
        }
        .frame(maxWidth: 420)
        .padding(.horizontal, BSmartSpacing.large)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(BSmartColor.ink)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trade.dock.\(symbol.lowercased())")
        .sheet(isPresented: $showsExternalVenues) {
            NavigationStack {
                ScrollView {
                    ExternalTradingVenuesView(symbol: symbol)
                        .padding(BSmartSpacing.large)
                }
                .accessibilityIdentifier("trade.external.sheet")
                .background(BSmartColor.ink)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { Group {
                        Button("Done".bSmartLocalized) { showsExternalVenues = false }
                    }.buttonStyle(.bSmartToolbar) }.bSmartHideSystemBackground()
                }
            }
            .presentationDetents([.height(430)])
            .presentationDragIndicator(.visible)
            .bSmartPage()
        }
    }
}

private struct BSmartTradeDockModifier: ViewModifier {
    let symbol: String
    let opinionSource: OpinionTradeSource?
    let marketCoin: String?
    let onTradeDismiss: (() -> Void)?

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            BSmartTradeDock(symbol: symbol, opinionSource: opinionSource, marketCoin: marketCoin, onTradeDismiss: onTradeDismiss)
        }
    }
}

extension View {
    func bSmartTradeDock(symbol: String, opinionSource: OpinionTradeSource? = nil, marketCoin: String? = nil, onTradeDismiss: (() -> Void)? = nil) -> some View {
        modifier(BSmartTradeDockModifier(symbol: symbol, opinionSource: opinionSource, marketCoin: marketCoin, onTradeDismiss: onTradeDismiss))
    }
}

struct BSmartTradeSheet: View {
    @StateObject private var store: HyperliquidTradingStore

    let symbol: String
    let initialSide: PaperTradeSide
    let onClose: () -> Void
    let coin: String?
    let initialAmount: String
    let initialReduction: Bool

    init(symbol: String, initialSide: PaperTradeSide, store: HyperliquidTradingStore,
         coin: String? = nil, initialAmount: String = "", initialReduction: Bool = false,
         onClose: @escaping () -> Void) {
        self.symbol = symbol
        self.initialSide = initialSide
        self.onClose = onClose
        self.coin = coin; self.initialAmount = initialAmount; self.initialReduction = initialReduction
        _store = StateObject(wrappedValue: store)
    }

    var body: some View {
        NavigationStack {
            HyperliquidTradingView(
                symbol: symbol,
                initialSide: initialSide,
                presentation: .quick,
                initialCoin: coin, initialAmount: initialAmount, initialReduction: initialReduction
            )
                .padding(BSmartSpacing.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(BSmartColor.ink)
                .toolbar(.hidden, for: .navigationBar)
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.bSmartPlain)
            .foregroundStyle(BSmartColor.secondaryText)
            .accessibilityLabel("Close".bSmartLocalized)
            .accessibilityIdentifier("trade.close")
            .padding(.top, BSmartSpacing.large)
            .padding(.trailing, BSmartSpacing.large)
        }
        .environmentObject(store)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(BSmartColor.ink)
        .bSmartPage()
    }
}
