import SwiftUI

struct AcrossWithdrawalDestination: View {
    @EnvironmentObject private var account: AccountAccessStore
    @EnvironmentObject private var deviceWallet: DeviceWalletStore
    @State private var store: AcrossWithdrawalStore?
    @State private var sessionWallet: DeviceWalletSummary?
    @State private var amount = ""
    @State private var recipient = ""
    @State private var errorMessage: String?
    @Environment(\.scenePhase) private var scenePhase

    private var wallet: DeviceWalletSummary? {
        guard case .verified(let wallet) = deviceWallet.state, wallet.canAuthorizeTransactions,
              account.identity?.id == wallet.accountID else { return nil }
        return wallet
    }

    private var walletReady: Bool {
        guard let wallet, let sessionWallet else { return false }
        return wallet.accountID == sessionWallet.accountID && wallet.address == sessionWallet.address
            && wallet.provider == sessionWallet.provider
    }

    private var sessionID: String {
        "\(account.identity?.id.uuidString ?? ""):\(wallet?.address ?? ""):\(wallet?.provider.rawValue ?? "")"
    }

    var body: some View {
        Group {
            if let sessionWallet, let store, account.identity?.id == sessionWallet.accountID {
                AcrossWithdrawalView(wallet: sessionWallet, store: store,
                                     enabled: account.configuration.acrossWithdrawalsEnabled == true,
                                     walletReady: walletReady, amount: $amount, recipient: $recipient)
            } else if let errorMessage {
                Text(errorMessage).padding(24)
            } else if account.identity == nil {
                NavigationLink { TradingAccountView() } label: {
                    Label("Sign in".bSmartLocalized, systemImage: "person.crop.circle").frame(minHeight: 48)
                }
            } else if deviceWallet.isBusy || account.isBusy {
                ProgressView()
            } else if wallet == nil {
                VStack(spacing: 20) {
                    DeviceWalletPanel()
                }.padding(24)
            } else { ProgressView() }
        }
        .task(id: sessionID) {
            if let sessionWallet, account.identity?.id != sessionWallet.accountID {
                resetSession()
            }
            guard let wallet else { return }
            if let sessionWallet, sessionWallet.accountID == wallet.accountID,
               sessionWallet.address == wallet.address, sessionWallet.provider == wallet.provider { return }
            resetSession()
            do {
                store = try .init(service: account, signer: deviceWallet.signing) {
                    guard account.configuration.acrossWithdrawalsEnabled == true,
                          account.identity?.id == wallet.accountID,
                          case .verified(let current) = deviceWallet.state else { return false }
                    return current.accountID == wallet.accountID && current.address == wallet.address
                        && current.provider == wallet.provider && current.canAuthorizeTransactions
                }
                sessionWallet = wallet
            } catch { errorMessage = FundingJournalError.unavailable.localizedDescription }
        }
        .task(id: "\(account.identity?.id.uuidString ?? "")-\(account.isBusy)-\(scenePhase == .active)") {
            guard account.identity != nil, !account.isBusy, scenePhase == .active, wallet == nil else { return }
            await deviceWallet.prepare()
        }
        .background(BSmartColor.ink).foregroundStyle(BSmartColor.primaryText)
        .navigationTitle("Withdraw".bSmartLocalized).navigationBarTitleDisplayMode(.inline)
        .bSmartPage()
    }

    private func resetSession() {
        store?.invalidate()
        store = nil
        sessionWallet = nil
        amount = ""
        recipient = ""
        errorMessage = nil
    }
}

struct AcrossWithdrawalSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AcrossWithdrawalDestination()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done".bSmartLocalized) { dismiss() }
                            .accessibilityIdentifier("withdraw.dismiss")
                    }
                }
        }
        .presentationDetents([.large])
    }
}
