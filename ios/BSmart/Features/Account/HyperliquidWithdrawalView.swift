import SwiftUI

struct HyperliquidWithdrawalDestination: View {
    @EnvironmentObject private var account: AccountAccessStore
    @EnvironmentObject private var deviceWallet: DeviceWalletStore
    @State private var store: HyperliquidWithdrawalStore?
    @State private var errorMessage: String?

    private var wallet: DeviceWalletSummary? {
        guard case .verified(let wallet) = deviceWallet.state, wallet.canAuthorizeTransactions,
              account.identity?.id == wallet.accountID else { return nil }
        return wallet
    }

    var body: some View {
        Group {
            if let wallet, let store {
                HyperliquidWithdrawalView(wallet: wallet, store: store, enabled: account.configuration.withdrawalsEnabled == true)
                    .id(wallet.accountID.uuidString + wallet.address)
            } else if let errorMessage {
                Text(errorMessage).padding(24)
            } else if wallet == nil {
                ContentUnavailableView("Unlock your wallet to continue.".bSmartLocalized, systemImage: "lock.shield")
            } else { ProgressView() }
        }
        .task(id: wallet) {
            store?.invalidate(); store = nil; errorMessage = nil
            guard let wallet else { return }
            do {
                store = try .init(service: account, journal: FundingTransactionJournal()) {
                    account.configuration.withdrawalsEnabled == true && account.identity?.id == wallet.accountID
                        && deviceWallet.state == .verified(wallet)
                }
            } catch { errorMessage = FundingJournalError.unavailable.localizedDescription }
        }
        .background(BSmartColor.ink).foregroundStyle(BSmartColor.primaryText)
        .navigationTitle("Withdraw USDC".bSmartLocalized).navigationBarTitleDisplayMode(.inline)
        .bSmartPage()
    }
}

struct HyperliquidWithdrawalView: View {
    let wallet: DeviceWalletSummary
    @ObservedObject var store: HyperliquidWithdrawalStore
    let enabled: Bool
    @State private var amount = ""
    @State private var recipient = ""
    @State private var acknowledged = false
    @State private var operation: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label("Arbitrum · USDC", systemImage: "arrow.up.right")
                    .font(.headline).foregroundStyle(BSmartColor.brand)
                if !enabled {
                    Label("Withdrawals are not available yet.".bSmartLocalized, systemImage: "lock.shield")
                        .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recipient address".bSmartLocalized).font(.subheadline)
                    TextField("0x…", text: $recipient, axis: .vertical)
                        .font(.body.monospaced()).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focused).padding(14)
                        .background(BSmartColor.surface, in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityIdentifier("withdraw.recipient")
                    Button("Use my wallet".bSmartLocalized) { recipient = wallet.address }
                        .font(.subheadline).foregroundStyle(BSmartColor.brand).frame(minHeight: 44)
                }.disabled(store.isBusy || store.result != nil)
                HStack {
                    TextField("0", text: $amount).keyboardType(.decimalPad).focused($focused)
                        .font(.system(size: 30, weight: .semibold)).monospacedDigit()
                        .accessibilityIdentifier("withdraw.amount")
                    Text("USDC").font(.headline)
                }.padding(.vertical, 12).disabled(store.isBusy || store.result != nil)
                Divider()
                if let preview = store.preview {
                    metric("Withdrawable", preview.available + " USDC")
                    metric("Withdrawal amount", preview.intent.amount.wire + " USDC")
                    metric("CCTP fee cap", preview.fee.maximumCCTPFee.formatted(decimals: 6) + " USDC")
                    Text("HyperCore fees also apply. The received amount is lower than the withdrawal amount; the CCTP fee shown is not the total fee.".bSmartLocalized)
                        .font(.footnote).foregroundStyle(BSmartColor.secondaryText)
                    Toggle("I confirm the Arbitrum address and understand that transfers cannot be reversed.".bSmartLocalized,
                           isOn: $acknowledged).font(.subheadline).disabled(store.isBusy)
                }
                if let result = store.result { status(result) }
                if let error = store.errorMessage {
                    Text(error).font(.subheadline).foregroundStyle(BSmartColor.bear)
                        .accessibilityIdentifier("withdraw.error")
                }
                if store.result == nil {
                    Button {
                        focused = false
                        operation = Task {
                            if store.preview == nil { await store.review(amount: amount, recipient: recipient, wallet: wallet) }
                            else { await store.confirm(wallet: wallet) }
                        }
                    } label: {
                        HStack {
                            if store.isBusy { ProgressView() }
                            else { Image(systemName: store.preview == nil ? "arrow.up.right" : "lock.shield") }
                            Text((store.preview == nil ? "Review withdrawal" : "Confirm withdrawal").bSmartLocalized)
                        }.font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundStyle(BSmartColor.onAccent)
                            .background(BSmartColor.brand, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                        .disabled(!enabled || store.isBusy || (store.preview != nil && !acknowledged) || scenePhase != .active)
                        .accessibilityIdentifier("withdraw.confirm")
                }
            }.padding(24).frame(maxWidth: 520).frame(maxWidth: .infinity)
        }
        .tint(BSmartColor.brand).scrollDismissesKeyboard(.interactively)
        .onChange(of: amount) { _, _ in resetReview() }
        .onChange(of: recipient) { _, _ in resetReview() }
        .onChange(of: enabled) { _, value in if !value { clear() } }
        .onChange(of: scenePhase) { _, value in if value == .background { clear() } }
        .onDisappear { clear() }
        .overlay { if scenePhase != .active { BSmartColor.ink.ignoresSafeArea() } }
        .toolbar { ToolbarItemGroup(placement: .keyboard) {
            Spacer(); Button("Done".bSmartLocalized) { focused = false }
        } }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title.bSmartLocalized).foregroundStyle(BSmartColor.secondaryText)
            Spacer(); Text(value).monospacedDigit()
        }.font(.subheadline)
    }

    @ViewBuilder private func status(_ record: HyperliquidWithdrawalRecord) -> some View {
        if case .accepted = record.acknowledgement {
            Label("Withdrawal submitted".bSmartLocalized, systemImage: "checkmark.circle")
                .foregroundStyle(BSmartColor.brand)
            Text("Processing to Arbitrum. Submission does not mean the funds have arrived.".bSmartLocalized)
                .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
        } else if case .rejected(let reason) = record.acknowledgement {
            Label("Withdrawal rejected".bSmartLocalized, systemImage: "exclamationmark.circle")
                .foregroundStyle(BSmartColor.bear)
            Text(reason).font(.subheadline)
        } else {
            Text(HyperliquidWithdrawalError.recoveryRequired.localizedDescription)
                .font(.subheadline).foregroundStyle(BSmartColor.gold)
        }
    }

    private func resetReview() { acknowledged = false; store.invalidate() }
    private func clear() { operation?.cancel(); operation = nil; focused = false; resetReview() }
}
