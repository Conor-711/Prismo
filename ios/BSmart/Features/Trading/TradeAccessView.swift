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
    case prominent
    case side
}

struct BSmartTradeButton: View {
    @EnvironmentObject private var trading: HyperliquidTradingStore
    let symbol: String
    var style: BSmartTradeButtonStyle = .compact
    var initialSide: PaperTradeSide = .long
    var opinionSource: OpinionTradeSource? = nil
    var onTradeDismiss: (() -> Void)? = nil

    @State private var showsTrading = false

    private var accent: Color {
        initialSide == .long ? BSmartColor.bull : BSmartColor.bear
    }

    private var title: String {
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
            HStack(spacing: style == .side ? 5 : 7) {
                if style == .compact {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 10, weight: .bold))
                }
                Text(title)
                    .font(.system(size: style == .compact ? 11 : 15, weight: .semibold))
            }
            .foregroundStyle(style == .compact ? accent : BSmartColor.onAccent)
            .padding(.horizontal, style == .compact ? 12 : 14)
            .frame(maxWidth: style == .prominent ? .infinity : nil)
            .frame(height: style == .compact ? 32 : 44)
            .background {
                if style == .compact {
                    Capsule().fill(accent.opacity(0.11))
                } else {
                    RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous)
                        .fill(accent)
                }
            }
            .overlay {
                if style == .compact {
                    Capsule().stroke(accent.opacity(0.7), lineWidth: 0.8)
                } else {
                    RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 0.6)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("%@ %@".bSmartLocalized(title, symbol.uppercased()))
        .accessibilityIdentifier(accessibilityIdentifier)
        .sheet(isPresented: $showsTrading, onDismiss: { onTradeDismiss?() }) {
            BSmartTradeSheet(symbol: symbol, initialSide: initialSide, store: trading.makeSession()) {
                showsTrading = false
            }
            .environment(\.opinionTradeSource, opinionSource?.matches(symbol: symbol) == true ? opinionSource : nil)
        }
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
                    .foregroundStyle(Color.white.opacity(0.88))
                    .lineLimit(1)
            }

            Spacer(minLength: 2)

            BSmartTradeButton(symbol: symbol, style: .side, initialSide: .long)
            BSmartTradeButton(symbol: symbol, style: .side, initialSide: .short)
        }
        .padding(.horizontal, 12)
        .frame(width: width, height: 52)
        .background(Color.black.opacity(0.82))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.11)).frame(height: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trade.card.\(symbol.lowercased())")
    }
}

struct BSmartTradeDock: View {
    let symbol: String
    var opinionSource: OpinionTradeSource? = nil
    var onTradeDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            BSmartTradeButton(symbol: symbol, style: .prominent, initialSide: .short, opinionSource: opinionSource, onTradeDismiss: onTradeDismiss)
            BSmartTradeButton(symbol: symbol, style: .prominent, initialSide: .long, opinionSource: opinionSource, onTradeDismiss: onTradeDismiss)
        }
        .frame(maxWidth: 420)
        .padding(.horizontal, BSmartSpacing.large)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(BSmartColor.ink)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trade.dock.\(symbol.lowercased())")
    }
}

private struct BSmartTradeDockModifier: ViewModifier {
    let symbol: String
    let opinionSource: OpinionTradeSource?
    let onTradeDismiss: (() -> Void)?

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            BSmartTradeDock(symbol: symbol, opinionSource: opinionSource, onTradeDismiss: onTradeDismiss)
        }
    }
}

extension View {
    func bSmartTradeDock(symbol: String, opinionSource: OpinionTradeSource? = nil, onTradeDismiss: (() -> Void)? = nil) -> some View {
        modifier(BSmartTradeDockModifier(symbol: symbol, opinionSource: opinionSource, onTradeDismiss: onTradeDismiss))
    }
}

private struct BSmartTradeSheet: View {
    @StateObject private var store: HyperliquidTradingStore

    let symbol: String
    let initialSide: PaperTradeSide
    let onClose: () -> Void

    init(symbol: String, initialSide: PaperTradeSide, store: HyperliquidTradingStore, onClose: @escaping () -> Void) {
        self.symbol = symbol
        self.initialSide = initialSide
        self.onClose = onClose
        _store = StateObject(wrappedValue: store)
    }

    var body: some View {
        NavigationStack {
                HyperliquidTradingView(
                    symbol: symbol,
                    initialSide: initialSide,
                    presentation: .quick,
                    onClose: onClose
                )
                .padding(BSmartSpacing.large)
            .background(BSmartColor.ink)
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .topTrailing) {
                if store.activeMarket == nil {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .frame(width: 44, height: 44)
                    }
                    .foregroundStyle(BSmartColor.secondaryText)
                    .accessibilityLabel("Close".bSmartLocalized)
                    .accessibilityIdentifier("trade.close")
                }
            }
        }
        .environmentObject(store)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(BSmartColor.ink)
        .bSmartPage()
    }
}
