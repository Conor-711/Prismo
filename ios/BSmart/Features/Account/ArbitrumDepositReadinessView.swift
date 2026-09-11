import SwiftUI

struct ArbitrumDepositReadinessView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 12) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 38)).foregroundStyle(BSmartColor.sky)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("USDC").font(.title2.bold())
                        Text("Arbitrum One").font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                    }
                }
                row("Network", value: "Arbitrum One")
                row("Asset", value: "Native USDC")
                row("Transfer route", value: "Circle CCTP")
                Divider().overlay(BSmartColor.line)
                Label("Deposits are not open yet".bSmartLocalized, systemImage: "lock.fill")
                    .font(.headline)
                    .accessibilityIdentifier("account.deposit-locked")
                Text("No receiving address is available until wallet creation, recovery and deposit verification are ready.".bSmartLocalized)
                    .font(.body).foregroundStyle(BSmartColor.secondaryText)
                CCTPDepositEstimateView()
                Divider().overlay(BSmartColor.line)
                VStack(alignment: .leading, spacing: 16) {
                    Label("Only native USDC on Arbitrum One. Do not send USDC.e or use another network.".bSmartLocalized,
                          systemImage: "exclamationmark.triangle")
                    Label("Moving USDC into Hyperliquid requires ETH on Arbitrum for network fees.".bSmartLocalized,
                          systemImage: "fuelpump")
                    Label("USDC in your wallet is not yet a Hyperliquid trading balance.".bSmartLocalized,
                          systemImage: "arrow.right.arrow.left")
                }
                .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
            }
            .padding(24).frame(maxWidth: 520, alignment: .leading).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(BSmartColor.ink)
        .foregroundStyle(BSmartColor.primaryText)
        .navigationTitle("Deposit USDC".bSmartLocalized)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("account.deposit-screen")
        .bSmartPage()
    }

    private func row(_ title: String, value: String) -> some View {
        HStack {
            Text(title.bSmartLocalized).foregroundStyle(BSmartColor.secondaryText)
            Spacer(minLength: 16)
            Text(value.bSmartLocalized).fontWeight(.semibold)
        }.font(.subheadline)
    }
}
