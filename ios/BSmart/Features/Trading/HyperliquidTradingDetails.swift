import SwiftUI

struct HyperliquidTradingDetails: View {
    @EnvironmentObject private var trading: HyperliquidTradingStore
    @EnvironmentObject private var paper: PaperTradingEngine
    @State private var showsDetails = false
    @State private var pendingClose: PaperTradingPosition?
    @State private var errorMessage: String?

    private var currentPosition: PaperTradingPosition? {
        paper.account.positions.first { $0.coin == trading.activeMarket?.coin }
    }

    var body: some View {
        if let market = trading.activeMarket {
            VStack(alignment: .leading, spacing: 20) {
                positionPanel(market)
                DisclosureGroup(isExpanded: $showsDetails) {
                    VStack(spacing: 20) {
                        HStack(spacing: 0) {
                            accountMetric("Equity", paper.account.equity)
                            accountMetric("Margin", paper.account.marginUsed)
                            accountMetric("Unrealized", paper.account.unrealizedPnL, signed: true)
                        }
                        marketMetrics(market)
                    }
                    .padding(.top, 16)
                } label: {
                    HStack {
                        Text("Available".bSmartLocalized)
                            .foregroundStyle(BSmartColor.secondaryText)
                        Spacer()
                        Text(paper.account.availableBalance.formatted(.bSmartDollars))
                            .fontWeight(.semibold).monospacedDigit()
                            .foregroundStyle(BSmartColor.primaryText)
                    }
                    .font(.subheadline)
                    .accessibilityIdentifier("trading-account.summary")
                }
                .tint(BSmartColor.secondaryText)
                .padding(.vertical, 12)
                recentExecutions
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(BSmartColor.bear)
                }
            }
            .confirmationDialog("Close position".bSmartLocalized, isPresented: Binding(
                get: { pendingClose != nil },
                set: { if !$0 { pendingClose = nil } }
            ), titleVisibility: .visible) {
                Button("Close position".bSmartLocalized, role: .destructive) {
                    guard let position = pendingClose else { return }
                    close(position: position, market: market)
                    pendingClose = nil
                }
            }
        }
    }

    private func close(position: PaperTradingPosition, market: HyperliquidPerpMarket) {
        guard TradeAmountInput.quoteIsCurrent(market.updatedAt) else {
            errorMessage = "Waiting for price".bSmartLocalized
            return
        }
        do {
            try paper.closePosition(coin: position.coin, market: market)
            errorMessage = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func accountMetric(_ label: String, _ value: Double, signed: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.bSmartLocalized)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(BSmartColor.tertiaryText)
            Text(value.formatted(
                .bSmartDollars
                    .precision(.fractionLength(2))
                    .sign(strategy: signed ? .always() : .automatic)
            ))
                .font(.caption.weight(.bold))
                .foregroundStyle(signed ? (value >= 0 ? BSmartColor.bull : BSmartColor.bear) : BSmartColor.primaryText)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, BSmartSpacing.small)
    }

    private func marketMetrics(_ market: HyperliquidPerpMarket) -> some View {
        HStack(spacing: 0) {
            compactMetric("Oracle", market.oraclePrice.bSmartMarketPrice)
            Divider().overlay(BSmartColor.line)
            compactMetric(
                "Funding / h",
                market.fundingRate.formatted(.percent.precision(.fractionLength(4)).sign(strategy: .always())),
                color: market.fundingRate > 0 ? BSmartColor.bear : BSmartColor.bull
            )
            Divider().overlay(BSmartColor.line)
            compactMetric("24h Volume", market.dayNotionalVolume.bSmartCompactUSD)
            Divider().overlay(BSmartColor.line)
            compactMetric("Open Interest", (market.openInterest * market.markPrice).bSmartCompactUSD)
        }
        .frame(height: 50)
        .background(BSmartColor.recessed)
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous)
                .stroke(BSmartColor.line, lineWidth: 0.5)
        }
    }

    private func compactMetric(_ label: String, _ value: String, color: Color = BSmartColor.primaryText) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.bSmartLocalized)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(BSmartColor.tertiaryText)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
    }

    @ViewBuilder
    private func positionPanel(_ market: HyperliquidPerpMarket) -> some View {
        if let position = currentPosition {
            VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
                HStack {
                    Text("OPEN POSITION".bSmartLocalized)
                        .font(.system(size: 10, weight: .black))
                        .tracking(0.8)
                        .foregroundStyle(BSmartColor.tertiaryText)
                    Spacer()
                    Text("%@ · %dx".bSmartLocalized(
                        (position.side == .long ? "LONG" : "SHORT").bSmartLocalized,
                        position.leverage
                    ))
                        .font(.caption.weight(.black))
                        .foregroundStyle(position.side == .long ? BSmartColor.bull : BSmartColor.bear)
                }

                HStack(alignment: .firstTextBaseline) {
                    Text(position.unrealizedPnL.formatted(
                        .bSmartDollars
                            .precision(.fractionLength(2))
                            .sign(strategy: .always())
                    ))
                        .font(.title3.weight(.black))
                        .foregroundStyle(position.unrealizedPnL >= 0 ? BSmartColor.bull : BSmartColor.bear)
                        .monospacedDigit()
                    Text(position.returnOnMargin.formatted(
                        .percent.precision(.fractionLength(2)).sign(strategy: .always())
                    ))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BSmartColor.secondaryText)
                        .monospacedDigit()
                    Spacer()
                    Button("Close position".bSmartLocalized) {
                        pendingClose = position
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BSmartColor.primaryText)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(BSmartColor.chartControl)
                    .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control))
                }

                HStack(spacing: 0) {
                    positionMetric("Position value", position.notional.bSmartCompactUSD)
                    positionMetric("Entry price", position.entryPrice.bSmartMarketPrice)
                    positionMetric("Mark price", market.markPrice.bSmartMarketPrice)
                    positionMetric("Liquidation price", position.liquidationPrice?.bSmartMarketPrice ?? "—")
                }
            }
            .bSmartPanel(border: (position.side == .long ? BSmartColor.bull : BSmartColor.bear).opacity(0.35))
            .accessibilityIdentifier("trading-position.\(position.coin)")
        }
    }

    private func positionMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.bSmartLocalized)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(BSmartColor.tertiaryText)
            Text(value)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var recentExecutions: some View {
        let executions = Array(paper.account.executions.filter { $0.coin == trading.activeMarket?.coin }.prefix(5))
        if !executions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("RECENT FILLS".bSmartLocalized)
                    .font(.system(size: 10, weight: .black))
                    .tracking(0.8)
                    .foregroundStyle(BSmartColor.tertiaryText)
                    .padding(.bottom, BSmartSpacing.small)

                ForEach(executions) { execution in
                    HStack(spacing: BSmartSpacing.small) {
                        Circle()
                            .fill(execution.side == .long ? BSmartColor.bull : BSmartColor.bear)
                            .frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(execution.symbol) · \(execution.kind.title)")
                                .font(.caption.weight(.bold))
                            Text("\(execution.size.formatted()) @ \(execution.price.bSmartMarketPrice)")
                                .font(.caption2)
                                .foregroundStyle(BSmartColor.tertiaryText)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(execution.notional.bSmartCompactUSD)
                                .font(.caption.weight(.bold))
                            Text(execution.executedAt.formatted(date: .omitted, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(BSmartColor.tertiaryText)
                        }
                    }
                    .padding(.vertical, 9)
                    if execution.id != executions.last?.id {
                        Divider().overlay(BSmartColor.line)
                    }
                }
            }
            .bSmartPanel()
        }
    }

}
