import SwiftUI

struct TickerOwnHoldingsSection: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var account: AccountAccessStore
    @EnvironmentObject private var wallet: DeviceWalletStore
    @Environment(\.scenePhase) private var scenePhase
    let symbol: String

    private var external: PortfolioPosition? {
        model.position(for: symbol).flatMap { $0.isPosition ? $0 : nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your position".bSmartLocalized).font(.headline)
                Spacer()
            }
            if let external {
                accountHeading("External holdings", value: externalWeight(external))
                PortfolioHoldingRow(holding: PortfolioHoldingSnapshot(external: external))
            }
            if account.identity == nil {
                NavigationLink { TradingAccountView() } label: {
                    Label("Sign in".bSmartLocalized, systemImage: "person.crop.circle")
                        .frame(minHeight: 44)
                }
            } else if case .verified(let local) = wallet.state, local.accountID == account.identity?.id {
                TradingPositionsView(wallet: local, title: "Internal account", symbol: symbol)
                    .id(local.accountID.uuidString + local.address)
            } else if wallet.isBusy || account.isBusy {
                BSmartSkeletonRows(style: .simple, count: 1)
            } else if case .recoveryRequired = wallet.state {
                NavigationLink { DeviceWalletRecoveryView() } label: {
                    Label("Restore wallet".bSmartLocalized, systemImage: "lock.shield")
                        .frame(minHeight: 44)
                }
            } else {
                if let error = wallet.errorMessage {
                    Text(error).font(.subheadline).foregroundStyle(BSmartColor.bear)
                }
                Button("Retry".bSmartLocalized) { Task { await wallet.prepare() } }
                    .frame(minHeight: 44)
            }
        }
        .padding(.vertical, 16)
        .overlay(alignment: .top) { Divider().overlay(BSmartColor.line) }
        .overlay(alignment: .bottom) { Divider().overlay(BSmartColor.line) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ticker.holdings.\(symbol)")
        .task(id: "\(account.walletAccountID?.uuidString ?? "")-\(account.isBusy)-\(scenePhase == .active)") {
            guard account.identity != nil, !account.isBusy, scenePhase == .active else { return }
            await wallet.prepare()
        }
    }

    private func accountHeading(_ title: String, value: String?) -> some View {
        HStack {
            Text(title.bSmartLocalized)
            Spacer()
            if let value { Text(value).monospacedDigit() }
        }
        .font(.caption.weight(.medium)).foregroundStyle(BSmartColor.secondaryText)
    }

    private func externalWeight(_ position: PortfolioPosition) -> String? {
        let values = model.heldPositions.map { PortfolioHoldingSnapshot(external: $0).value }
        guard values.allSatisfy({ $0 != nil }), let value = PortfolioHoldingSnapshot(external: position).value else { return nil }
        let total = values.compactMap { $0 }.reduce(0, +)
        guard total > 0 else { return nil }
        return "Portfolio weight %@".bSmartLocalized((value / total).formatted(.percent.precision(.fractionLength(1))))
    }
}

struct TickerAboutSection: View {
    let symbol: String
    let companyName: String
    let profile: TickerProfile?
    let market: HyperliquidPerpMarket?
    let isCrypto: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("About this asset".bSmartLocalized).font(.headline)
                Spacer()
                if let url = profile?.source {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right.square").frame(width: 44, height: 44)
                    }
                    .tint(BSmartColor.brand)
                    .accessibilityLabel("Company website".bSmartLocalized)
                }
            }
            HStack(spacing: 12) {
                BSmartAssetMark(ticker: symbol, size: 32, isCrypto: isCrypto)
                Text(companyName).font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let profile {
                Text(profile.summary).font(.subheadline)
                    .foregroundStyle(BSmartColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(profile.category.bSmartLocalized).font(.caption.weight(.medium))
                    .foregroundStyle(BSmartColor.brand)
            } else {
                Text("Company profile unavailable".bSmartLocalized)
                    .font(.subheadline).foregroundStyle(BSmartColor.tertiaryText)
            }
            if let market {
                Divider().overlay(BSmartColor.line)
                HStack(alignment: .top, spacing: 12) {
                    fact("24h volume", market.dayNotionalVolume.bSmartCompactUSD)
                    fact("Open interest", (market.openInterest * market.markPrice).bSmartCompactUSD)
                    fact("Max leverage", "\(market.maxLeverage)x")
                }
                Text("Perpetual contract. Trading this market does not confer ownership of the underlying asset.".bSmartLocalized)
                    .font(.caption).foregroundStyle(BSmartColor.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ticker.about.\(symbol)")
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.bSmartLocalized).font(.caption2).foregroundStyle(BSmartColor.tertiaryText)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
