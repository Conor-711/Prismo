import SwiftUI

struct LiveOrderAmountPanel: View {
    @Binding var amount: TradeAmountInput
    @Binding var leverage: Int
    let summary: LiveOrderEntrySummary?
    let accent: Color
    let market: HyperliquidPerpMarket?
    let isLocked: Bool
    var reducing = false
    @State private var showsChart = false

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Text((reducing ? "Position to close" : "Exposure").bSmartLocalized).foregroundStyle(BSmartColor.secondaryText)
                    if !reducing { Text(dollars(notional)).monospacedDigit() }
                }.font(.subheadline)
                Text(reducing ? amount.text + "%" : "$" + amount.text)
                    .font(.system(size: 64, weight: .medium, design: .rounded)).monospacedDigit()
                    .foregroundStyle(amount.value > 0 ? BSmartColor.primaryText : BSmartColor.tertiaryText)
                    .lineLimit(1).minimumScaleFactor(0.4)
                    .frame(maxWidth: .infinity, minHeight: 76)
                    .accessibilityIdentifier("trade.amount")
            }
            TradeLeveragePicker(value: $leverage, maximum: summary?.account.market.maximumLeverage ?? market?.maxLeverage ?? 5,
                                accent: accent, isLocked: isLocked || reducing || summary?.account.position != nil)
            HStack(alignment: .top, spacing: 8) {
                figure(reducing ? "Quantity" : "Est. liq.",
                       reducing ? summary?.reductionQuantity(percent: Int(amount.text) ?? 0) ?? "--" : "--", alignment: .leading)
                figure("Exposure", dollars(notional), alignment: .center)
                figure("Estimated fee", dollars(notional.flatMap { summary?.fee(notional: $0) }), alignment: .trailing)
            }.padding(.vertical, 4)
            if !isLocked {
                if market != nil { modeControl }
                if showsChart, let market {
                    LiveOrderMarketChart(market: market)
                } else {
                    HStack(spacing: 8) {
                        ForEach(reducing ? [25, 50, 75, 100] : [10, 50, 100, 300], id: \.self) { value in
                            Button { amount.setExact(String(value)) } label: {
                                Text(reducing ? "\(value)%" : "$\(value)").font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 38)
                                    .background(BSmartColor.recessed, in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain).accessibilityIdentifier("trade.amount.preset.\(value)")
                        }
                    }
                    keypad
                }
            }
        }
    }

    private var notional: String? {
        if reducing { return summary?.reductionNotional(percent: Int(amount.text) ?? 0) }
        let text = amount.text.hasSuffix(".") ? String(amount.text.dropLast()) : amount.text
        if let summary { return summary.notional(margin: text) }
        guard let amount = try? HyperliquidOrderDecimal(text) else { return nil }
        return try? HyperliquidExactValue(amount).multiplied(by: .init(UInt64(max(1, leverage))))
            .rounded(decimalPlaces: 6, up: false).wire
    }

    private var modeControl: some View {
        HStack(spacing: 12) {
            Rectangle().fill(BSmartColor.line).frame(height: 0.5)
            HStack(spacing: 2) {
                modeButton(false, symbol: "circle.grid.3x3.fill", label: "Keypad")
                modeButton(true, symbol: "chart.bar.xaxis", label: "Candlestick chart")
            }.padding(3).background(BSmartColor.recessed, in: RoundedRectangle(cornerRadius: 8))
            Rectangle().fill(BSmartColor.line).frame(height: 0.5)
        }
    }

    private func modeButton(_ chart: Bool, symbol: String, label: String) -> some View {
        Button { showsChart = chart } label: {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
                .foregroundStyle(showsChart == chart ? accent : BSmartColor.tertiaryText)
                .frame(width: 44, height: 38)
                .background(showsChart == chart ? BSmartColor.selectedControlSurface : .clear, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).accessibilityLabel(label.bSmartLocalized)
            .accessibilityAddTraits(showsChart == chart ? .isSelected : [])
            .accessibilityIdentifier(chart ? "trade.mode.chart" : "trade.mode.keypad")
    }

    private var keypad: some View {
        let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "delete"]
        return Grid(horizontalSpacing: 8, verticalSpacing: 2) {
            ForEach(0..<4) { row in
                GridRow {
                    ForEach(0..<3) { column in
                        let key = keys[row * 3 + column]
                        Button {
                            if reducing, key == "." { return }
                            amount.enter(key)
                            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.4)
                        } label: {
                            Group {
                                if key == "delete" { Image(systemName: "delete.left").font(.system(size: 22)) }
                                else { Text(key).font(.system(size: 28, weight: .regular, design: .rounded)) }
                            }.frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(reducing && key == ".")
                            .opacity(reducing && key == "." ? 0 : 1)
                            .accessibilityLabel(key == "delete" ? "Delete".bSmartLocalized : key)
                            .accessibilityIdentifier("trade.key.\(key)")
                    }
                }
            }
        }
    }

    private func dollars(_ text: String?) -> String { text.map { "$" + $0 } ?? "--" }
    private func figure(_ label: String, _ value: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(label.bSmartLocalized).font(.caption).foregroundStyle(BSmartColor.secondaryText)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .top))
    }
}

private struct LiveOrderMarketChart: View {
    @EnvironmentObject private var trading: HyperliquidTradingStore
    let market: HyperliquidPerpMarket
    var body: some View {
        LiveOrderChartSession(market: market, store: trading.makeSession()).id(market.coin)
    }
}

private struct LiveOrderChartSession: View {
    let market: HyperliquidPerpMarket
    @StateObject private var store: HyperliquidTradingStore
    init(market: HyperliquidPerpMarket, store: HyperliquidTradingStore) {
        self.market = market; _store = StateObject(wrappedValue: store)
    }
    var body: some View {
        HyperliquidMarketChart(market: market, compact: true)
            .environmentObject(store)
            .task { await store.selectMarket(market) }
            .task(id: store.chartRange) { await store.reloadCandles() }
    }
}
