import SwiftUI

struct BSmartMarketAssetMark: View {
    let ticker: String
    var isCrypto = false

    var body: some View {
        BSmartAssetMark(ticker: ticker, size: 48, isCrypto: isCrypto)
            .background(BSmartColor.surface, in: Circle())
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(BSmartColor.line, lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

struct BSmartMarketRow: View {
    let entry: AppTickerCatalogEntry
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 12 : 14) {
            BSmartMarketAssetMark(ticker: entry.symbol, isCrypto: entry.isCrypto)
            VStack(alignment: .leading, spacing: compact ? 4 : 7) {
                HStack(spacing: 6) {
                    Text(entry.symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.75)
                    if let leverage = entry.maxLeverage {
                        Text("\(leverage)x")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(BSmartColor.sky)
                            .padding(.horizontal, 5).padding(.vertical, 3)
                            .background(BSmartColor.sky.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                Text(volumeLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(BSmartColor.secondaryText)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .accessibilityIdentifier("portfolio.volume.\(entry.symbol)")
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: compact ? 4 : 7) {
                Text(entry.price?.bSmartMarketPrice ?? "—")
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.75)
                    .accessibilityIdentifier("portfolio.price.\(entry.symbol)")
                HStack(spacing: 3) {
                    if let change = entry.dayChange {
                        Image(systemName: change < 0 ? "arrowtriangle.down.fill" : "arrowtriangle.up.fill")
                            .font(.system(size: 8, weight: .bold))
                        Text(abs(change).formatted(.percent.precision(.fractionLength(2))))
                    } else {
                        Text("—")
                    }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(changeColor)
                .accessibilityLabel("24h " + (entry.dayChange.map {
                    $0.formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always()))
                } ?? "—"))
                .accessibilityIdentifier("portfolio.change.\(entry.symbol)")
            }
            .monospacedDigit()
            .layoutPriority(1)
        }
        .foregroundStyle(BSmartColor.primaryText)
        .padding(.vertical, compact ? 8 : 13)
        .frame(minHeight: compact ? 70 : 82)
        .contentShape(Rectangle())
    }

    private var volumeLabel: String {
        let volume = entry.volume24h?.bSmartCompactUSD ?? "—"
        return volume + " " + "Volume".bSmartLocalized
    }

    private var changeColor: Color {
        guard let change = entry.dayChange else { return BSmartColor.secondaryText }
        return change == 0 ? BSmartColor.secondaryText : (change > 0 ? BSmartColor.bull : BSmartColor.bear)
    }
}
