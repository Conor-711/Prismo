import SwiftUI

struct HyperliquidTradeLoadingView: View {
    let symbol: String
    let presentation: HyperliquidTradingPresentation
    var reducing = false
    var chartRange: HyperliquidChartRange = .oneDay
    var isCrypto = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if presentation == .quick {
                HStack(spacing: 12) {
                    BSmartAssetMark(ticker: symbol, size: 44, isCrypto: isCrypto)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(symbol).font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(BSmartColor.primaryText)
                        TradeLoadingBlock(width: 72, height: 12)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 6) {
                        TradeLoadingBlock(width: 82, height: 21)
                        Text("Market order".bSmartLocalized)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BSmartColor.secondaryText)
                    }
                    .padding(.trailing, 44)
                }
                LiveOrderLoadingPanel(reducing: reducing)
            } else {
                HyperliquidChartLoadingView(selectedRange: chartRange)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: presentation == .quick ? .infinity : nil,
               alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trade.market.loading")
    }
}

struct LiveOrderLoadingPanel: View {
    var reducing = false

    var body: some View {
        VStack(spacing: 10) {
            ScrollView {
                VStack(spacing: 12) {
                    VStack(spacing: 8) {
                        HStack {
                            Text((reducing ? "Position to close" : "Exposure").bSmartLocalized)
                                .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                            TradeLoadingBlock(width: 70, height: 15)
                        }
                        TradeLoadingBlock(width: 190, height: 64, radius: 8)
                            .frame(maxWidth: .infinity, minHeight: 76)
                    }
                    HStack(spacing: 26) {
                        TradeLoadingBlock(width: 52, height: 28)
                        TradeLoadingBlock(width: 62, height: 32)
                        TradeLoadingBlock(width: 52, height: 28)
                    }
                    .frame(height: 58)
                    Text("Leverage".bSmartLocalized)
                        .font(.caption).foregroundStyle(BSmartColor.secondaryText)
                    HStack(alignment: .top, spacing: 8) {
                        figure(reducing ? "Quantity" : "Est. liq.")
                        figure("Exposure")
                        figure("Estimated fee")
                    }
                    .padding(.vertical, 4)
                    HStack(spacing: 12) {
                        Rectangle().fill(BSmartColor.line).frame(height: 0.5)
                        Image(systemName: "circle.grid.3x3.fill")
                        Image(systemName: "chart.bar.xaxis")
                        Rectangle().fill(BSmartColor.line).frame(height: 0.5)
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(BSmartColor.tertiaryText)
                    .frame(height: 44)
                    HStack(spacing: 8) {
                        ForEach(reducing ? [25, 50, 75, 100] : [10, 50, 100, 300], id: \.self) { value in
                            Text(reducing ? "\(value)%" : "$\(value)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(BSmartColor.tertiaryText)
                                .frame(maxWidth: .infinity, minHeight: 38)
                                .background(BSmartColor.recessed, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    Grid(horizontalSpacing: 8, verticalSpacing: 2) {
                        ForEach(0..<4) { row in
                            GridRow {
                                ForEach(0..<3) { column in
                                    let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "delete"]
                                    let key = keys[row * 3 + column]
                                    Group {
                                        if key == "delete" { Image(systemName: "delete.left") }
                                        else { Text(key) }
                                    }
                                    .font(.system(size: 28, weight: .regular, design: .rounded))
                                    .foregroundStyle(BSmartColor.tertiaryText)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
            HStack {
                TradeLoadingBlock(width: 115, height: 16)
                Spacer()
                Image(systemName: "arrow.clockwise")
                Text("MAX".bSmartLocalized)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(BSmartColor.tertiaryText)
            .frame(height: 36)
            RoundedRectangle(cornerRadius: 8)
                .fill(BSmartColor.recessed)
                .frame(height: 60)
                .overlay(alignment: .leading) {
                    Image(systemName: "arrow.right")
                        .font(.headline)
                        .foregroundStyle(BSmartColor.tertiaryText)
                        .frame(width: 48, height: 48)
                        .background(BSmartColor.elevated, in: RoundedRectangle(cornerRadius: 7))
                        .padding(6)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityLabel("Loading Hyperliquid market".bSmartLocalized)
        .accessibilityIdentifier("trade.order.loading")
    }

    private func figure(_ label: String) -> some View {
        VStack(spacing: 5) {
            Text(label.bSmartLocalized)
                .font(.caption).foregroundStyle(BSmartColor.secondaryText)
                .lineLimit(1).minimumScaleFactor(0.7)
            TradeLoadingBlock(width: 54, height: 15)
        }
        .frame(maxWidth: .infinity)
    }
}

struct HyperliquidChartLoadingView: View {
    let selectedRange: HyperliquidChartRange

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 9) {
                    TradeLoadingBlock(width: 154, height: 28)
                    TradeLoadingBlock(width: 68, height: 17)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 9) {
                    TradeLoadingBlock(width: 90, height: 20)
                    Text("Open Interest".bSmartLocalized)
                        .font(.caption).foregroundStyle(BSmartColor.secondaryText)
                }
            }
            .frame(minHeight: 72, alignment: .top)
            HyperliquidChartLoadingPlot()
                .frame(height: 330)
            HStack(spacing: 2) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 40, height: 44)
                Rectangle().fill(BSmartColor.line).frame(width: 1, height: 18)
                ForEach(HyperliquidChartRange.allCases) { range in
                    Text(range.rawValue)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(selectedRange == range ? BSmartColor.primaryText : BSmartColor.tertiaryText)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background {
                            if selectedRange == range {
                                RoundedRectangle(cornerRadius: 8).fill(BSmartColor.elevated)
                                    .padding(.vertical, 5)
                            }
                        }
                }
            }
            .foregroundStyle(BSmartColor.tertiaryText)
        }
        .accessibilityIdentifier("hyperliquid.chart.loading")
    }
}

struct HyperliquidChartLoadingPlot: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                for fraction in [0.25, 0.5, 0.75] {
                    let y = geometry.size.height * fraction
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                }
            }
            .stroke(BSmartColor.line.opacity(0.7), lineWidth: 0.6)
        }
        .accessibilityHidden(true)
    }
}

private struct TradeLoadingBlock: View {
    let width: CGFloat
    let height: CGFloat
    var radius: CGFloat = 5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDimmed = false

    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(BSmartColor.elevated)
            .opacity(isDimmed ? 0.58 : 1)
            .frame(width: width, height: height)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true)) {
                    isDimmed = true
                }
            }
            .accessibilityHidden(true)
    }
}
