import SwiftUI

struct PortfolioHoldingRow: View {
    let holding: PortfolioHoldingSnapshot

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                BSmartMarketAssetMark(ticker: holding.symbol)
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

private struct PortfolioCompactColumns {
    let name: CGFloat
    let quantity: CGFloat
    let price: CGFloat
    let pnl: CGFloat

    init(width: CGFloat) {
        name = width * 0.34
        quantity = width * 0.22
        price = width * 0.22
        pnl = width - name - quantity - price
    }
}

struct PortfolioCompactHoldingHeader: View {
    var body: some View {
        GeometryReader { geometry in
            let columns = PortfolioCompactColumns(width: geometry.size.width)
            HStack(spacing: 0) {
                heading("Name / ticker", width: columns.name, alignment: .leading)
                heading("Qty / value", width: columns.quantity, alignment: .trailing)
                heading("Price / cost", width: columns.price, alignment: .trailing)
                heading("P&L", width: columns.pnl, alignment: .trailing)
            }
        }
        .frame(height: 26)
    }

    private func heading(_ title: String, width: CGFloat, alignment: Alignment) -> some View {
        Text(title.bSmartLocalized)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(BSmartColor.secondaryText)
            .lineLimit(1).minimumScaleFactor(0.75)
            .frame(width: width, alignment: alignment)
    }
}

struct PortfolioCompactHoldingRow: View {
    let holding: PortfolioHoldingSnapshot
    let companyName: String
    var isCrypto = false

    var body: some View {
        GeometryReader { geometry in
            let columns = PortfolioCompactColumns(width: geometry.size.width)
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    BSmartMarketAssetMark(ticker: holding.symbol, isCrypto: isCrypto)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(companyName).font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(BSmartColor.primaryText)
                        Text(holding.symbol).font(.system(size: 12))
                            .foregroundStyle(BSmartColor.secondaryText)
                    }
                    .lineLimit(1).minimumScaleFactor(0.85)
                }
                .frame(width: columns.name, alignment: .leading)
                values(primary: holding.quantity > 0
                       ? holding.quantity.formatted(.number.precision(.fractionLength(0...8))) : "--",
                       secondary: holding.value.map { $0.formatted(.bSmartDollars.precision(.fractionLength(2))) } ?? "--",
                       width: columns.quantity)
                    .accessibilityIdentifier("portfolio.position.value.\(holding.symbol)")
                values(primary: holding.price?.bSmartMarketPrice ?? "--",
                       secondary: holding.averageCost?.bSmartMarketPrice ?? "--",
                       width: columns.price)
                values(primary: holding.gain.map {
                           $0.formatted(.bSmartDollars.precision(.fractionLength(2)).sign(strategy: .always()))
                       } ?? "--",
                       secondary: holding.gainPercent.map {
                           $0.formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always()))
                       } ?? "--",
                       width: columns.pnl,
                       color: gainColor)
                    .accessibilityIdentifier("portfolio.position.pnl.\(holding.symbol)")
            }
        }
        .frame(height: 70)
        .contentShape(Rectangle())
    }

    private func values(primary: String, secondary: String, width: CGFloat,
                        color: Color = BSmartColor.primaryText) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(primary).font(.system(size: 15, weight: .semibold)).foregroundStyle(color)
            Text(secondary).font(.system(size: 12)).foregroundStyle(
                color == BSmartColor.primaryText ? BSmartColor.secondaryText : color)
        }
        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
        .frame(width: width, alignment: .trailing)
    }

    private var gainColor: Color {
        guard let gain = holding.gain, gain != 0 else { return BSmartColor.secondaryText }
        return gain > 0 ? BSmartColor.bull : BSmartColor.bear
    }
}
