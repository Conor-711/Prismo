import SwiftUI

struct HyperCoreBalanceView: View {
    let wallet: DeviceWalletSummary
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var balances: HyperCoreBalanceStore
    @State private var refreshTask: Task<Void, Never>?

    init(wallet: DeviceWalletSummary, service: AccountWalletServicing) {
        self.wallet = wallet
        _balances = StateObject(wrappedValue: HyperCoreBalanceStore(service: service))
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let current = balances.currentSnapshot(wallet: wallet, now: context.date)
            HyperCoreBalanceContent(snapshot: current, expired: balances.snapshot != nil && current == nil,
                                    isLoading: balances.isLoading, errorMessage: balances.errorMessage) {
                refreshTask?.cancel()
                refreshTask = Task { await balances.refresh(wallet: wallet) }
            }
        }
        .onDisappear { clear() }
        .onChange(of: wallet) { _, _ in clear() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { clear() } }
        .accessibilityIdentifier("wallet.hypercore-balances")
    }

    private func clear() {
        refreshTask?.cancel(); refreshTask = nil; balances.clear()
    }
}

struct HyperCoreBalanceContent: View {
    let snapshot: HyperCoreBalanceSnapshot?
    let expired: Bool
    let isLoading: Bool
    let errorMessage: String?
    let refresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("On Hyperliquid".bSmartLocalized).font(.headline)
                Spacer(minLength: 12)
                Button(action: refresh) {
                    if isLoading { ProgressView().frame(width: 44, height: 44) }
                    else { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }
                }
                .buttonStyle(.plain).foregroundStyle(BSmartColor.brand).disabled(isLoading)
                .accessibilityLabel("Check Hyperliquid balances".bSmartLocalized)
                .accessibilityIdentifier("wallet.check-hypercore-balances")
            }
            if let snapshot {
                Text(snapshot.mode.title).font(.subheadline.weight(.medium)).foregroundStyle(BSmartColor.brand)
                row(snapshot.mode.usesSharedBalance ? "USDC balance" : "Spot USDC", amount: snapshot.usdc.formatted)
                row("USDC on hold", amount: snapshot.held.formatted)
                if let perps = snapshot.perps {
                    Divider().overlay(BSmartColor.line)
                    row("Default perps equity", amount: perps.equity.formatted)
                    row("Default perps withdrawable", amount: perps.withdrawable.formatted)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("Checked".bSmartLocalized)
                    Spacer(minLength: 12)
                    Text(snapshot.checkedAt, style: .time).monospacedDigit()
                }.font(.caption).foregroundStyle(BSmartColor.secondaryText)
            } else {
                Text((expired ? "Balance check expired" : "Not checked").bSmartLocalized)
                    .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                    .accessibilityIdentifier(expired ? "wallet.hypercore-expired" : "wallet.hypercore-unchecked")
            }
            if let errorMessage {
                Text(errorMessage).font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("wallet.hypercore-error")
            }
            Text("Balances do not confirm an individual deposit or the amount available for a new trade.".bSmartLocalized)
                .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ title: String, amount: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(title.bSmartLocalized).fixedSize().foregroundStyle(BSmartColor.secondaryText)
                Spacer(minLength: 0)
                Text(amount).fixedSize().monospacedDigit().fontWeight(.semibold)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(title.bSmartLocalized).foregroundStyle(BSmartColor.secondaryText)
                Text(amount).monospacedDigit().fontWeight(.semibold)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.subheadline).foregroundStyle(BSmartColor.primaryText)
        .accessibilityElement(children: .combine)
    }
}
