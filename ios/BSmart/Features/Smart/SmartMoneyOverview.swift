import SwiftUI

struct SmartMoneySourceStatus: View {
    let signals: [SmartMoneySignal]

    private var updatedAt: Date? { signals.compactMap(\.sourceUpdatedAt).max() }
    private var delayed: Bool { updatedAt.map { Date().timeIntervalSince($0) > 1_800 } ?? true }
    private var source: String {
        let values = Set(signals.map(\.resolvedSource))
        guard values.count == 1 else { return "Mixed sources" }
        switch values.first {
        case "hyperdash": return "Hyperdash"
        case "hyperdash_cached": return "Hyperdash cache"
        case "hyperliquid_fallback": return "Hyperliquid fallback"
        default: return "Unverified"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: delayed ? "clock.badge.exclamationmark" : "checkmark.shield")
                .foregroundStyle(delayed ? BSmartColor.gold : BSmartColor.brand)
            Text(source.bSmartLocalized + " · Copy Score")
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                Text((delayed ? "Delayed" : "Current").bSmartLocalized)
                    .foregroundStyle(delayed ? BSmartColor.gold : BSmartColor.brand)
                if let updatedAt { Text(updatedAt.bSmartDataTimestamp).monospacedDigit() }
            }
        }
        .font(.caption).foregroundStyle(BSmartColor.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 12)
    }
}

struct SmartMoneyCohortSummary: View {
    let signals: [SmartMoneySignal]
    @ScaledMetric(relativeTo: .subheadline) private var columnWidth = 125.0
    private var positions: [SmartMoneyPosition] { signals.flatMap(\.resolvedPositions) }
    private var long: Double {
        positions.filter { $0.direction.caseInsensitiveCompare("Long") == .orderedSame }
            .reduce(0) { $0 + abs($1.notional) }
    }
    private var short: Double {
        positions.filter { $0.direction.caseInsensitiveCompare("Short") == .orderedSame }
            .reduce(0) { $0 + abs($1.notional) }
    }
    private var topAsset: String? {
        Dictionary(grouping: positions, by: \.symbol)
            .map { (symbol: $0.key, notional: $0.value.reduce(0) { $0 + abs($1.notional) }) }
            .max { $0.notional < $1.notional }?.symbol
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cohort positioning".bSmartLocalized).font(.headline)
            GeometryReader { proxy in
                let share = long + short > 0 ? long / (long + short) : 0
                HStack(spacing: 0) {
                    Rectangle().fill(BSmartColor.bull).frame(width: proxy.size.width * share)
                    Rectangle().fill(long + short > 0 ? BSmartColor.bear : BSmartColor.line)
                }
            }
            .frame(height: 5).clipShape(Capsule())
            .accessibilityHidden(true)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: columnWidth), alignment: .leading)], alignment: .leading, spacing: 16) {
                metric("Long", value: long.bSmartCompactUSD, color: BSmartColor.bull)
                metric("Short", value: short.bSmartCompactUSD, color: BSmartColor.bear)
                metric("Gross", value: (long + short).bSmartCompactUSD, color: BSmartColor.primaryText)
                if let topAsset { metric("Top exposure", value: topAsset, color: BSmartColor.primaryText) }
            }
            Divider().overlay(BSmartColor.line)
        }
        .padding(.top, 8).padding(.bottom, 8)
    }

    private func metric(_ title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.bSmartLocalized).font(.caption).foregroundStyle(BSmartColor.secondaryText)
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(color).monospacedDigit()
        }.fixedSize(horizontal: false, vertical: true)
    }
}
