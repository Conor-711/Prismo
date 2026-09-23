import SwiftUI

struct CCTPTransferDestination: View {
    @EnvironmentObject private var account: AccountAccessStore
    @EnvironmentObject private var deviceWallet: DeviceWalletStore

    var body: some View {
        Group {
            if !account.configuration.depositsEnabled {
                ContentUnavailableView("Deposits are not open yet".bSmartLocalized, systemImage: "lock.shield")
            } else if case .verified(let wallet) = deviceWallet.state, wallet.canAuthorizeTransactions,
                      account.identity?.id == wallet.accountID {
                CCTPTransferLoader(wallet: wallet, service: account, signer: deviceWallet.signing) {
                    account.configuration.depositsEnabled && account.identity?.id == wallet.accountID
                        && deviceWallet.state == .verified(wallet)
                }.id(wallet.accountID.uuidString + wallet.address)
            } else {
                ContentUnavailableView("Unlock your wallet to continue.".bSmartLocalized,
                                       systemImage: "lock.shield")
            }
        }
        .background(BSmartColor.ink).foregroundStyle(BSmartColor.primaryText)
        .navigationTitle("Transfer to Hyperliquid".bSmartLocalized).navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("deposit.transfer-screen")
        .bSmartPage()
    }
}

private struct CCTPTransferLoader: View {
    let wallet: DeviceWalletSummary
    let service: AccountWalletServicing
    let signer: any FundingDeviceSigning
    let enabled: () -> Bool
    @State private var store: CCTPTransferStore?
    @State private var failed = false
    @State private var retryID = UUID()

    var body: some View {
        Group {
            if let store { CCTPTransferView(wallet: wallet, store: store) }
            else if failed {
                VStack(spacing: 20) {
                    Text(FundingJournalError.unavailable.localizedDescription)
                    Button("Try again".bSmartLocalized) { retryID = UUID() }
                }.padding(24)
            } else { ProgressView() }
        }
        .task(id: retryID) {
            do {
                guard enabled() else { return }
                let preparation = CCTPDepositPreparation(service: service, signer: signer,
                    journal: try FundingTransactionJournal(), isEnabled: enabled)
                store = CCTPTransferStore(preparation: preparation, isEnabled: enabled)
                failed = false
            } catch { failed = true }
        }
    }
}

struct CCTPTransferView: View {
    let wallet: DeviceWalletSummary
    @ObservedObject var store: CCTPTransferStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var amount = ""
    @State private var operation: Task<Void, Never>?
    @State private var now = Date()
    @FocusState private var amountFocused: Bool

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    CCTPTransferContent(display: store.display, isBusy: store.isBusy, now: now,
                        errorMessage: store.errorMessage, amount: $amount, amountFocused: $amountFocused,
                        primary: advance, cancel: cancel)
                    NavigationLink { FundingHistoryDestination() } label: {
                        HStack {
                            Label("Deposit history".bSmartLocalized, systemImage: "clock.arrow.circlepath")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }.font(.subheadline.weight(.semibold)).frame(minHeight: 48)
                    }.foregroundStyle(BSmartColor.brand).accessibilityIdentifier("deposit.transfer-history")
                }.padding(24).frame(maxWidth: 520).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .disabled(scenePhase != .active)
        .overlay { if scenePhase != .active { BSmartColor.ink.ignoresSafeArea() } }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done".bSmartLocalized) { amountFocused = false }
            }
        }
        .onDisappear { clear() }
        .task { await store.restore(wallet: wallet) }
        .task(id: store.display.phase) {
            // No timer traverses the text input while the user types.
            now = Date()
            guard [.authorization, .networkFee, .signed].contains(store.display.phase) else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                now = Date()
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .background { clear() } }
        .onChange(of: wallet) { _, _ in clear() }
    }

    private func advance() {
        guard scenePhase == .active, !store.isBusy else { return }
        amountFocused = false
        let value = amount, phase = store.display.phase
        operation = Task {
            switch phase {
            case .amount: await store.prepareTransfer(amount: value, wallet: wallet)
            case .authorization: await store.authorize()
            case .networkFee:
                if store.display.canConfirm(at: Date()) { await store.confirmTransfer() }
                else { await store.restore(wallet: wallet) }
            case .signed: await store.submit()
            case .recovery: await store.restore(wallet: wallet)
            default: break
            }
        }
    }

    private func cancel() {
        guard scenePhase == .active, !store.isBusy else { return }
        operation = Task { await store.cancelReview() }
    }

    private func clear() {
        operation?.cancel(); operation = nil; amountFocused = false
        store.invalidate()
    }
}
