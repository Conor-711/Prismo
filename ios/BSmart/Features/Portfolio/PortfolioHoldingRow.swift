import SwiftUI

struct PortfolioHoldingRow: View {
    let holding: PortfolioHoldingSnapshot

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                BSmartAssetMark(ticker: holding.symbol, size: 42)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(holding.symbol).font(.system(size: 16, weight: .semibold))
                    HStack(spacing: 6) {
                        Text(holding.quantity > 0 ? holding.quantity.formatted(.number.precision(.fractionLength(0...4))) : "—")
                        if let side = holding.side, let leverage = holding.leverage {
                            Text("\(leverage)x " + (side == .long ? "Long" : "Short").bSmartLocalized)
                                .foregroundStyle(side == .long ? BSmartColor.bull : BSmartColor.bear)
                        } else {
                            Text("Shares".bSmartLocalized)
                        }
                    }
                    .font(.system(size: 12)).foregroundStyle(BSmartColor.secondaryText)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 5) {
                    Text(holding.price?.bSmartMarketPrice ?? "—")
                        .font(.system(size: 17, weight: .semibold))
                        .accessibilityIdentifier("portfolio.price.\(holding.symbol)")
                    Text("Current price".bSmartLocalized)
                        .font(.system(size: 11)).foregroundStyle(BSmartColor.secondaryText)
                }
            }
            HStack(alignment: .top, spacing: 8) {
                metric("Average cost", value: holding.averageCost?.bSmartMarketPrice ?? "—", key: "cost")
                metric(holding.side == nil ? "Position value" : "Position size",
                       value: holding.value.map { $0.formatted(.bSmartDollars.precision(.fractionLength(2))) } ?? "—",
                       key: "value")
                VStack(alignment: .trailing, spacing: 5) {
                    Text((holding.side == nil ? "Holding P&L" : "Margin P&L").bSmartLocalized)
                        .font(.system(size: 11)).foregroundStyle(BSmartColor.secondaryText)
                    Text(holding.gain.map { $0.formatted(.bSmartDollars.precision(.fractionLength(2)).sign(strategy: .always())) } ?? "—")
                        .font(.system(size: 13, weight: .semibold))
                        .accessibilityIdentifier("portfolio.pnl.\(holding.symbol)")
                    Text(holding.gainPercent.map { $0.formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always())) } ?? "—")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(gainColor)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .monospacedDigit()
        .foregroundStyle(BSmartColor.primaryText)
        .lineLimit(1).minimumScaleFactor(0.75)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }

    private func metric(_ label: String, value: String, key: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.bSmartLocalized).font(.system(size: 11)).foregroundStyle(BSmartColor.secondaryText)
            Text(value).font(.system(size: 13, weight: .semibold))
                .accessibilityIdentifier("portfolio.\(key).\(holding.symbol)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var gainColor: Color {
        guard let gain = holding.gain, gain != 0 else { return BSmartColor.secondaryText }
        return gain > 0 ? BSmartColor.bull : BSmartColor.bear
    }
}
