import SwiftUI

struct TradeOrderComposer: View {
    @EnvironmentObject private var paper: PaperTradingEngine
    let market: HyperliquidPerpMarket
    let initialSide: PaperTradeSide
    // Provenance only. Paper executions must never publish real-trader events.
    let opinionSource: OpinionTradeSource?
    let onComplete: () -> Void

    @State private var amount = TradeAmountInput()
    @State private var side: PaperTradeSide
    @State private var leverage = 5
    @State private var errorMessage: String?
    @State private var execution: PaperTradeExecution?
    @State private var showsChart = false

    init(market: HyperliquidPerpMarket, initialSide: PaperTradeSide, opinionSource: OpinionTradeSource? = nil, onComplete: @escaping () -> Void) {
        self.market = market
        self.initialSide = initialSide
        self.opinionSource = opinionSource?.matches(symbol: market.symbol) == true ? opinionSource : nil
        self.onComplete = onComplete
        _side = State(initialValue: initialSide)
    }

    private var accent: Color { side == .long ? BSmartColor.bull : BSmartColor.bear }
    private var position: PaperTradingPosition? { paper.account.positions.first { $0.coin == market.coin } }
    private var preview: PaperOrderPreview? {
        try? paper.preview(side: side, margin: amount.value, leverage: leverage, market: market)
    }
    private var maximumMargin: Double {
        TradeAmountInput.maximumMargin(
            balance: paper.account.availableBalance,
            leverage: leverage,
            feeRate: PaperTradingEngine.simulatedTakerFeeRate
        )
    }

    var body: some View {
        VStack(spacing: 10) {
            if let execution {
                completion(execution)
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                VStack(spacing: 12) {
                amountDisplay
                TradeLeveragePicker(value: $leverage, maximum: market.maxLeverage, accent: accent, isLocked: position != nil)
                orderFigures
                inputModeControl
                if showsChart {
                    HyperliquidMarketChart(market: market, compact: true)
                } else {
                    VStack(spacing: 12) {
                        amountPresets
                        keypad
                    }
                }
                }
                .padding(.bottom, 8)
                }
                .scrollIndicators(.hidden)
                availableBalance
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(BSmartColor.bear)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("trading-order.error")
                }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let current = TradeAmountInput.quoteIsCurrent(market.updatedAt, now: context.date)
                    let affordable = position?.side != side && position != nil
                        || (preview.map { $0.margin + $0.fee <= paper.account.availableBalance } ?? false)
                    TradeSlideToConfirm(
                        title: current ? (amount.value > 0 ? orderTitle : "Enter an amount".bSmartLocalized) : "Waiting for price".bSmartLocalized,
                        accent: accent,
                        isEnabled: current && preview != nil && affordable && !market.isDelisted,
                        action: placeOrder
                    )
                    .id("\(market.coin)-\(side.rawValue)-\(leverage)-\(amount.text)")
                }
            }
        }
        .onAppear {
            leverage = min(max(1, position?.leverage ?? 5), market.maxLeverage)
        }
        .onChange(of: market.maxLeverage) { _, maximum in
            leverage = min(max(1, leverage), maximum)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(execution == nil ? "trade.composer" : "trade.order.filled")
    }

    private var inputModeControl: some View {
        HStack(spacing: 12) {
            Rectangle().fill(BSmartColor.line).frame(height: 0.5)
            HStack(spacing: 2) {
                modeButton(chart: false, symbol: "circle.grid.3x3.fill", title: "Keypad")
                modeButton(chart: true, symbol: "chart.bar.xaxis", title: "Candlestick chart")
            }
            .padding(3)
            .background(BSmartColor.recessed, in: RoundedRectangle(cornerRadius: 8))
            Rectangle().fill(BSmartColor.line).frame(height: 0.5)
        }
    }

    private func modeButton(chart: Bool, symbol: String, title: String) -> some View {
        Button {
            showsChart = chart
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(showsChart == chart ? accent : BSmartColor.tertiaryText)
                .frame(width: 44, height: 38)
                .background(showsChart == chart ? BSmartColor.elevated : .clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title.bSmartLocalized)
        .accessibilityAddTraits(showsChart == chart ? .isSelected : [])
        .accessibilityIdentifier(chart ? "trade.mode.chart" : "trade.mode.keypad")
    }

    private var amountDisplay: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("Exposure".bSmartLocalized).foregroundStyle(BSmartColor.secondaryText)
                Text((amount.value * Double(leverage)).bSmartCompactUSD).monospacedDigit()
            }
            .font(.subheadline)
            Text("$" + amount.text)
                .font(.system(size: 64, weight: .medium, design: .rounded))
                .foregroundStyle(amount.value > 0 ? BSmartColor.primaryText : BSmartColor.tertiaryText)
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.45)
                .frame(maxWidth: .infinity, minHeight: 76)
                .accessibilityIdentifier("trade.amount")
        }
    }

    private var availableBalance: some View {
        HStack {
            Text("%@ available".bSmartLocalized(
                paper.account.availableBalance.formatted(.bSmartDollars)
            ))
            .font(.caption)
            .foregroundStyle(BSmartColor.secondaryText)
            .accessibilityIdentifier("trading-account.summary")
            Spacer()
            Button("MAX".bSmartLocalized) {
                amount.set(maximumMargin)
                errorMessage = nil
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(accent)
            .frame(minWidth: 44, minHeight: 32)
            .accessibilityIdentifier("trade.amount.max")
        }
    }

    private var amountPresets: some View {
        HStack(spacing: 8) {
            ForEach([10, 50, 100, 300], id: \.self) { dollars in
                Button {
                    amount.set(Double(dollars))
                    errorMessage = nil
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    Text("$\(dollars)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BSmartColor.primaryText)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(BSmartColor.recessed, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("trade.amount.preset.\(dollars)")
            }
        }
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
                    errorMessage = nil
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.4)
                } label: {
                    Group {
                        if key == "delete" {
                            Image(systemName: "delete.left").font(.system(size: 22))
                        } else {
                            Text(key).font(.system(size: 28, weight: .regular, design: .rounded))
                        }
                    }
                    .foregroundStyle(BSmartColor.primaryText)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(key == "delete" ? "Delete".bSmartLocalized : key)
                .accessibilityIdentifier("trade.key.\(key)")
                }
                }
            }
        }
    }

    private var orderFigures: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                figure("Est. liq.", preview?.estimatedLiquidationPrice?.bSmartMarketPrice ?? "—")
                    .frame(maxWidth: .infinity, alignment: .leading)
                figure("Exposure", preview?.notional.bSmartCompactUSD ?? "—", alignment: .center)
                    .frame(maxWidth: .infinity)
                figure("Estimated fee", preview?.fee.formatted(.bSmartDollars) ?? "—", alignment: .trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            if let position, position.side != side {
                Text("This order reduces or reverses your %@ position.".bSmartLocalized(
                    (position.side == .long ? "Long" : "Short").bSmartLocalized
                ))
                .font(.caption)
                .foregroundStyle(BSmartColor.gold)
                .fixedSize(horizontal: false, vertical: true)
            } else if amount.value > maximumMargin {
                Text("Insufficient available balance.".bSmartLocalized)
                    .font(.caption).foregroundStyle(BSmartColor.bear)
            }
        }
        .padding(.vertical, 4)
    }

    private func figure(_ label: String, _ value: String, alignment: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(label.bSmartLocalized).font(.caption).foregroundStyle(BSmartColor.secondaryText)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
    }

    private var orderTitle: String {
        if let position, position.side != side {
            return "Slide to %@".bSmartLocalized("Place order".bSmartLocalized)
        }
        return "Slide to %@ %@".bSmartLocalized(
            (side == .long ? "Long" : "Short").bSmartLocalized, market.symbol
        )
    }

    private func placeOrder() {
        guard execution == nil, TradeAmountInput.quoteIsCurrent(market.updatedAt), !market.isDelisted else { return }
        do {
            execution = try paper.placeMarketOrder(
                side: side, margin: amount.value, leverage: leverage, market: market
            )
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            errorMessage = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func completion(_ fill: PaperTradeExecution) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(accent)
            Text("Order filled".bSmartLocalized).font(.title2.weight(.bold))
            Text("\(fill.symbol) · \(fill.kind.title)")
                .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
            HStack {
                figure("Position value", fill.notional.formatted(.bSmartDollars))
                Spacer()
                figure("Fill price", fill.price.bSmartMarketPrice, alignment: .trailing)
            }
            Button(action: onComplete) {
                Text("Done".bSmartLocalized)
                    .font(.headline)
                    .foregroundStyle(BSmartColor.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(accent, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("trade.order.done")
        }
        .padding(.vertical, 48)
        .accessibilityElement(children: .contain)
    }
}
