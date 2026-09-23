import SwiftUI

struct PortfolioAppAccountView: View {
    @EnvironmentObject private var account: AccountAccessStore
    @EnvironmentObject private var wallet: DeviceWalletStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if case .verified(let local) = wallet.state, local.accountID == account.identity?.id {
                ManagedDepositView(account: account, showsHistory: false)
            } else {
                fallbackContent
            }
        }
        .navigationTitle("Deposit".bSmartLocalized).navigationBarTitleDisplayMode(.inline)
        .background(BSmartColor.ink).foregroundStyle(BSmartColor.primaryText)
        .task(id: "\(account.identity?.id.uuidString ?? "")-\(account.isBusy)-\(scenePhase == .active)") {
            guard account.identity != nil, !account.isBusy, scenePhase == .active else { return }
            await wallet.prepare()
        }
        .accessibilityIdentifier("portfolio.deposit.screen")
        .bSmartPage()
    }

    private var fallbackContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if account.identity == nil {
                    NavigationLink { TradingAccountView() } label: {
                        AccountActionRow(title: "Sign in", symbol: "person.crop.circle")
                    }
                } else if wallet.isBusy || account.isBusy {
                    BSmartSkeletonRows(style: .simple, count: 3)
                } else {
                    if let error = wallet.errorMessage {
                        Text(error).font(.subheadline).foregroundStyle(BSmartColor.bear)
                    }
                    if case .recoveryRequired = wallet.state {
                        NavigationLink { DeviceWalletRecoveryView() } label: {
                            AccountActionRow(title: "Restore wallet", symbol: "key")
                        }
                    } else {
                        Button("Try again".bSmartLocalized) { Task { await wallet.prepare() } }
                    }
                }
            }
            .buttonStyle(.plain).padding(24)
            .frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .safeAreaPadding(.bottom, 88)
    }
}
