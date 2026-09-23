import SwiftUI
import UIKit

struct ExternalTradingVenuesView: View {
    let symbol: String

    private var destinations: [ExternalTradeDestination] {
        ExternalTradeLinks.destinations(for: symbol)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                BSmartAssetMark(ticker: symbol, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(symbol.uppercased())
                        .font(.title3.weight(.bold))
                        .foregroundStyle(BSmartColor.primaryText)
                    Text("No Hyperliquid perpetual market found".bSmartLocalized)
                        .font(.subheadline)
                        .foregroundStyle(BSmartColor.secondaryText)
                }
            }

            if !destinations.isEmpty {
                Text("View on another platform".bSmartLocalized)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BSmartColor.primaryText)

                VStack(spacing: 0) {
                    ForEach(destinations) { destination in
                        Button {
                            open(destination)
                        } label: {
                            HStack(spacing: 12) {
                                Image(destination.logoAssetName)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 36, height: 36)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .accessibilityHidden(true)
                                Text(destination.name)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(BSmartColor.primaryText)
                                Spacer(minLength: 8)
                                Text(symbol.uppercased())
                                    .font(.subheadline.monospaced())
                                    .foregroundStyle(BSmartColor.secondaryText)
                                Image(systemName: "arrow.up.right")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BSmartColor.brand)
                            }
                            .frame(minHeight: 52)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("trade.external.\(destination.name.lowercased())")
                        if destination.id != destinations.last?.id {
                            Rectangle().fill(BSmartColor.softDivider).frame(height: 0.5)
                        }
                    }
                }
                Text("Opens the asset on an external platform. Trading availability depends on that platform.".bSmartLocalized)
                    .font(.caption)
                    .foregroundStyle(BSmartColor.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trade.external-venues")
    }

    private func open(_ destination: ExternalTradeDestination) {
        UIApplication.shared.open(destination.url, options: [.universalLinksOnly: true]) { opened in
            guard !opened else { return }
            Task { @MainActor in UIApplication.shared.open(destination.url) }
        }
    }
}
