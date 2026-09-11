import SwiftUI

struct ArbitrumWalletBalanceView: View {
    let wallet: DeviceWalletSummary
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var balances = ArbitrumWalletBalanceStore()
    @State private var refreshTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("On Arbitrum".bSmartLocalized).font(.headline)
                Spacer()
                Button {
                    refreshTask?.cancel()
                    refreshTask = Task { await balances.refresh(wallet: wallet) }
                } label: {
                    if balances.isLoading { ProgressView().frame(width: 44, height: 44) }
                    else { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }
                }
                .buttonStyle(.plain).foregroundStyle(BSmartColor.brand)
                .disabled(balances.isLoading)
                .accessibilityLabel("Check wallet balances".bSmartLocalized)
                .accessibilityIdentifier("wallet.check-balances")
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let current = balances.snapshot.flatMap { value in
                    (try? value.validate(wallet: wallet, now: context.date)) != nil ? value : nil
                }
                VStack(spacing: 12) {
                    row("USDC", amount: current?.usdc.formatted(decimals: 6))
                    row("ETH", amount: current?.eth.formatted(decimals: 18))
                }
                if balances.snapshot != nil, current == nil {
                    Text("Balance check expired".bSmartLocalized)
                        .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                }
            }
            Text("USDC in your wallet is not yet a Hyperliquid trading balance.".bSmartLocalized)
                .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
            if let error = balances.errorMessage {
                Text(error).font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                    .accessibilityIdentifier("wallet.balance-error")
            }
        }
        .accessibilityIdentifier("wallet.arbitrum-balances")
        .onDisappear { clear() }
        .onChange(of: wallet) { _, _ in clear() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { clear() } }
    }

    private func row(_ asset: String, amount: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(asset).foregroundStyle(BSmartColor.secondaryText)
            Spacer(minLength: 16)
            Text(amount ?? "--").monospacedDigit().fontWeight(.semibold)
                .lineLimit(1).minimumScaleFactor(0.75)
        }.font(.subheadline)
    }

    private func clear() {
        refreshTask?.cancel()
        refreshTask = nil
        balances.clear()
    }
}
