import SwiftUI

struct PortfolioAppAccountView: View {
    @EnvironmentObject private var account: AccountAccessStore
    @EnvironmentObject private var wallet: DeviceWalletStore

    var body: some View {
        Group {
            if case .verified(let local) = wallet.state, account.identity?.id == local.accountID {
                HyperCoreBalanceView(wallet: local, service: account)
                    .id(local.accountID.uuidString + local.address)
            } else {
                Label("Unlock your wallet to check balances.".bSmartLocalized, systemImage: "lock.shield")
                    .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("portfolio.app.live-balances")
    }
}
