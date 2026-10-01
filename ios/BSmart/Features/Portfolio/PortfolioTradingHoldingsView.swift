import SwiftUI

struct PortfolioTradingHoldingsView: View {
    @EnvironmentObject private var account: AccountAccessStore
    @EnvironmentObject private var wallet: DeviceWalletStore
    @Environment(\.scenePhase) private var scenePhase
    @Binding var isShowingWithdrawal: Bool
    @ObservedObject var portfolioStore: OwnerPortfolioStore
    @State private var isShowingDeposit = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Button { isShowingDeposit = true } label: {
                    Label("Deposit".bSmartLocalized, systemImage: "plus.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(BSmartColor.onAccent)
                        .background(BSmartColor.brand, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.bSmartPlain).accessibilityIdentifier("portfolio.deposit")
                Button { isShowingWithdrawal = true } label: {
                    Label("Withdraw".bSmartLocalized, systemImage: "arrow.up.right")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(BSmartColor.primaryText)
                        .background(BSmartColor.elevated, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.bSmartPlain).accessibilityIdentifier("portfolio.withdraw")
            }
            if account.identity == nil {
                NavigationLink { TradingAccountView() } label: {
                    Label("Sign in".bSmartLocalized, systemImage: "person.crop.circle")
                        .frame(minHeight: 44)
                }
            } else {
                if portfolioStore.accountID == account.identity?.id, let portfolio = portfolioStore.portfolio {
                    if portfolio.status == .ready {
                        FeedPublicPositionsView(positions: portfolio.positions)
                    } else {
                        Text("No linked trading wallet".bSmartLocalized)
                            .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                    }
                } else if portfolioStore.isLoading || account.isBusy {
                    BSmartSkeletonRows(style: .simple, count: 2)
                } else if !portfolioStore.failed {
                    Text("On-chain account unavailable".bSmartLocalized)
                        .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                }
                if portfolioStore.failed {
                    HStack(spacing: 12) {
                        Text("On-chain account unavailable".bSmartLocalized)
                            .font(.caption).foregroundStyle(BSmartColor.bear)
                        Button("Retry".bSmartLocalized) {
                            Task { await portfolioStore.load(account: account, force: true) }
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .frame(minHeight: 44)
                }
                if case .verified(let local) = wallet.state, local.accountID == account.identity?.id {
                    NavigationLink { TradingMarketsView() } label: {
                        Label("Trade".bSmartLocalized, systemImage: "plus.circle")
                            .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                    }
                }
                if case .recoveryRequired = wallet.state {
                    NavigationLink { DeviceWalletRecoveryView() } label: {
                        Label("Restore wallet".bSmartLocalized, systemImage: "lock.shield").frame(minHeight: 44)
                    }
                }
            }
        }
        .padding(.bottom, 96)
        .sheet(isPresented: $isShowingDeposit) {
            NavigationStack {
                PortfolioAppAccountView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) { Group {
                            Button("Done".bSmartLocalized) { isShowingDeposit = false }
                        }.buttonStyle(.bSmartToolbar) }.bSmartHideSystemBackground()
                    }
            }
            .presentationDetents([.large])
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("portfolio.app.positions")
        .task(id: "\(account.walletAccountID?.uuidString ?? "")-\(account.isBusy)-\(scenePhase == .active)") {
            guard account.identity != nil, !account.isBusy, scenePhase == .active else { return }
            await wallet.prepare()
        }
    }
}
