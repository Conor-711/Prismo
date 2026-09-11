import SwiftUI

struct LiveOrderAmountPanel: View {
    @Binding var amount: TradeAmountInput
    let summary: LiveOrderEntrySummary?
    let accent: Color
    let market: HyperliquidPerpMarket?
    let isLocked: Bool
    @State private var showsChart = false

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("Position value".bSmartLocalized).font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                Text("$" + amount.text)
                    .font(.system(size: 64, weight: .medium, design: .rounded)).monospacedDigit()
                    .foregroundStyle(amount.value > 0 ? BSmartColor.primaryText : BSmartColor.tertiaryText)
                    .lineLimit(1).minimumScaleFactor(0.4)
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .accessibilityIdentifier("trade.amount")
            }.padding(.top, 4)
            if let summary {
                TradeLeveragePicker(value: .constant(summary.leverage), maximum: summary.account.market.maximumLeverage,
                                    accent: accent, isLocked: true)
            } else {
                VStack(spacing: 6) {
                    Text("--x").font(.system(size: 23, weight: .semibold)).foregroundStyle(BSmartColor.tertiaryText)
                    Text("Leverage".bSmartLocalized).font(.caption).foregroundStyle(BSmartColor.secondaryText)
                }.frame(height: 78)
            }
            HStack(alignment: .top, spacing: 8) {
                figure("Margin", dollars(summary?.margin(notional: amount.text)), alignment: .leading)
                figure("Exposure", "$" + amount.text, alignment: .center)
                figure("Estimated fee", dollars(summary?.fee(notional: amount.text)), alignment: .trailing)
            }.padding(.vertical, 4)
            if !isLocked {
                if market != nil { modeControl }
                if showsChart, let market {
                    LiveOrderMarketChart(market: market)
                } else {
                    HStack(spacing: 8) {
                        ForEach([10, 50, 100, 300], id: \.self) { value in
                            Button { amount.setExact(String(value)) } label: {
                                Text("$\(value)").font(.subheadline.weight(.semibold))
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
                .background(showsChart == chart ? BSmartColor.elevated : .clear, in: RoundedRectangle(cornerRadius: 6))
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
                            amount.enter(key)
                            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.4)
                        } label: {
                            Group {
                                if key == "delete" { Image(systemName: "delete.left").font(.system(size: 22)) }
                                else { Text(key).font(.system(size: 28, weight: .regular, design: .rounded)) }
                            }.frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain)
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
