import Charts
import SwiftUI

struct HyperliquidMarketChart: View {
    @EnvironmentObject private var trading: HyperliquidTradingStore
    let market: HyperliquidPerpMarket
    var compact = false
    var activities: [TickerSmartActivityItem]? = nil
    @State private var selectedTime: Date?
    @State private var showsOpinions = false

    private var visibleActivities: [TickerSmartActivityItem] {
        TickerChartOpinion.visibleActivities(activities ?? [], symbol: market.symbol,
                                            candles: trading.candles, range: trading.chartRange)
    }

    private var selectedCandle: HyperliquidCandle? {
        guard let selectedTime else { return nil }
        return trading.candles.min {
            abs($0.openTime.timeIntervalSince(selectedTime)) < abs($1.openTime.timeIntervalSince(selectedTime))
        }
    }

    private var accent: Color {
        market.dayChangePercent >= 0 ? BSmartColor.bull : BSmartColor.bear
    }

    var body: some View {
        VStack(spacing: 16) {
            if !compact {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text((selectedCandle?.close ?? market.markPrice).bSmartMarketPrice)
                        .font(.system(size: 28, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.7)
                    if let selectedCandle {
                        Text(selectedCandle.openTime.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(BSmartColor.secondaryText)
                    } else {
                        HStack(spacing: 5) {
                            Text(market.dayChangePercent.formatted(
                                .percent.precision(.fractionLength(2)).sign(strategy: .always())
                            ))
                            .foregroundStyle(accent)
                            Text("24h").foregroundStyle(BSmartColor.tertiaryText)
                        }
                        .font(.subheadline.weight(.medium))
                    }
                }
                Spacer(minLength: 10)
                VStack(alignment: .trailing, spacing: 6) {
                    Text((market.openInterest * market.markPrice).bSmartCompactUSD)
                        .font(.headline).monospacedDigit()
                    Text("Open Interest".bSmartLocalized)
                        .font(.caption)
                        .foregroundStyle(BSmartColor.secondaryText)
                }
                .padding(.top, 6)
            }
            .frame(minHeight: 72, alignment: .top)
            }

            if trading.candles.isEmpty {
                Group {
                    if trading.isLoadingCandles { ProgressView().tint(BSmartColor.brand) }
                    else {
                        ContentUnavailableView("Price history unavailable".bSmartLocalized,
                                               systemImage: "chart.xyaxis.line")
                    }
                }
                .frame(maxWidth: .infinity, minHeight: compact ? 214 : 330)
            } else {
                priceChart
            }

            HStack(spacing: 2) {
                if !compact { Menu {
                    ForEach(HyperliquidChartStyle.allCases) { style in
                        Button {
                            trading.chartStyle = style
                        } label: {
                            Label(
                                (style == .line ? "Line chart" : "Candlestick chart").bSmartLocalized,
                                systemImage: style.symbol
                            )
                        }
                    }
                } label: {
                    Image(systemName: trading.chartStyle.symbol)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(BSmartColor.brand)
                        .frame(width: 40, height: 44)
                }
                .accessibilityLabel("Chart style".bSmartLocalized)
                .accessibilityIdentifier("trade.chart-style")
                }

                Rectangle().fill(BSmartColor.line).frame(width: 1, height: 18)
                ForEach(HyperliquidChartRange.allCases) { range in
                    Button {
                        selectedTime = nil
                        trading.chartRange = range
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        Text(range.rawValue)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(trading.chartRange == range ? BSmartColor.primaryText : BSmartColor.tertiaryText)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background {
                                if trading.chartRange == range {
                                    RoundedRectangle(cornerRadius: 8).fill(BSmartColor.elevated)
                                        .padding(.vertical, 5)
                                }
                            }
                    }
                    .accessibilityAddTraits(trading.chartRange == range ? .isSelected : [])
                    .accessibilityIdentifier("trade.range.\(range.rawValue)")
                }
            }
            .buttonStyle(.plain)
            if !compact, activities != nil {
                HStack(spacing: 16) {
                    HStack(spacing: 8) {
                        Label("Opinions".bSmartLocalized, systemImage: "person.crop.circle")
                            .font(.caption.weight(.semibold))
                        Toggle("Opinions".bSmartLocalized, isOn: $showsOpinions)
                            .labelsHidden()
                            .toggleStyle(.switch).tint(BSmartColor.brand)
                            .accessibilityIdentifier("ticker.chart.opinions-toggle")
                    }
                    .fixedSize()
                    Spacer(minLength: 0)
                    if showsOpinions {
                        BSmartDetailNavigationLink(id: "chart-activity-\(market.coin)-\(trading.chartRange.rawValue)") {
                            TickerChartActivityList(activities: visibleActivities, symbol: market.symbol,
                                                    range: trading.chartRange)
                        } label: {
                            HStack(spacing: 5) {
                                Text("%d updates".bSmartLocalized(visibleActivities.count))
                                Image(systemName: "chevron.right")
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BSmartColor.brand)
                            .frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("ticker.chart.all-activity")
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hyperliquid.chart")
    }

    private var priceChart: some View {
        BSmartPriceChart(
            series: BSmartPriceChartSeries(trading.candles.map {
                BSmartChartCandle(time: $0.openTime, interval: $0.closeTime.timeIntervalSince($0.openTime),
                                  open: $0.open, high: $0.high, low: $0.low, close: $0.close)
            }),
            showsCandles: compact || trading.chartStyle != .line,
            accent: accent, referencePrice: market.markPrice,
            intraday: trading.chartRange == .oneHour || trading.chartRange == .fourHours || trading.chartRange == .oneDay,
            identifier: "trade.price-chart",
            onSelection: { selectedTime = $0 }
        ) { proxy in
            if showsOpinions && !compact {
                TickerChartOpinionOverlay(
                    opinions: TickerChartOpinion.candidates(activities: visibleActivities, candles: trading.candles),
                    policy: TickerChartOpinionPolicy(range: trading.chartRange), proxy: proxy)
            }
        }
        .frame(height: compact ? 250 : 366)
        .id("\(market.coin)-\(trading.chartRange.rawValue)")
    }
}
