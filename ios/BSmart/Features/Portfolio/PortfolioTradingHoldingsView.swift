import SwiftUI

struct PortfolioTradingHoldingsView: View {
    @EnvironmentObject private var account: AccountAccessStore
    @EnvironmentObject private var wallet: DeviceWalletStore
    @Environment(\.scenePhase) private var scenePhase
    @Binding var isShowingWithdrawal: Bool
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
                .buttonStyle(.plain).accessibilityIdentifier("portfolio.deposit")
                Button { isShowingWithdrawal = true } label: {
                    Label("Withdraw".bSmartLocalized, systemImage: "arrow.up.right")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(BSmartColor.primaryText)
                        .background(BSmartColor.elevated, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain).accessibilityIdentifier("portfolio.withdraw")
            }
            if account.identity == nil {
                NavigationLink { TradingAccountView() } label: {
                    Label("Sign in".bSmartLocalized, systemImage: "person.crop.circle")
                        .frame(minHeight: 44)
                }
            } else if case .verified(let local) = wallet.state, local.accountID == account.identity?.id {
                TradingPositionsView(wallet: local, title: "Holdings", profileStyle: true)
                    .id(local.accountID.uuidString + local.address)
                NavigationLink { TradingMarketsView() } label: {
                    Label("Trade".bSmartLocalized, systemImage: "plus.circle")
                        .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                }
            } else if wallet.isBusy || account.isBusy {
                BSmartSkeletonRows(style: .simple, count: 2)
            } else {
                if let error = wallet.errorMessage {
                    Text(error).font(.subheadline).foregroundStyle(BSmartColor.bear)
                }
                if case .recoveryRequired = wallet.state {
                    NavigationLink { DeviceWalletRecoveryView() } label: {
                        Label("Restore wallet".bSmartLocalized, systemImage: "lock.shield").frame(minHeight: 44)
                    }
                } else {
                    Button("Retry".bSmartLocalized) { Task { await wallet.prepare() } }
                        .frame(minHeight: 44)
                }
            }
        }
        .padding(.bottom, 96)
        .sheet(isPresented: $isShowingDeposit) {
            NavigationStack {
                PortfolioAppAccountView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done".bSmartLocalized) { isShowingDeposit = false }
                        }
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
