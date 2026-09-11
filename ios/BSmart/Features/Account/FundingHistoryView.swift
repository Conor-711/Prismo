import SwiftUI

struct FundingHistoryDestination: View {
    @EnvironmentObject private var account: AccountAccessStore
    @EnvironmentObject private var deviceWallet: DeviceWalletStore

    var body: some View {
        Group {
            if case .verified(let wallet) = deviceWallet.state, account.walletAccountID == wallet.accountID {
                FundingHistoryLoader(wallet: wallet, service: account)
                    .id(wallet.accountID.uuidString + wallet.address)
            } else {
                ContentUnavailableView("Unlock wallet".bSmartLocalized, systemImage: "lock.shield")
            }
        }
        .navigationTitle("Deposit history".bSmartLocalized)
        .navigationBarTitleDisplayMode(.inline)
        .background(BSmartColor.ink)
        .foregroundStyle(BSmartColor.primaryText)
        .accessibilityIdentifier("deposit.history-screen")
        .bSmartPage()
    }
}

private struct FundingHistoryLoader: View {
    let wallet: DeviceWalletSummary
    let service: AccountWalletServicing
    @State private var store: FundingHistoryStore?
    @State private var failed = false
    @State private var retryID = UUID()

    var body: some View {
        Group {
            if let store { FundingHistoryView(wallet: wallet, store: store) }
            else if failed {
                VStack(spacing: 20) {
                    Label(FundingJournalError.unavailable.localizedDescription, systemImage: "exclamationmark.lock")
                    Button("Try again".bSmartLocalized) { retryID = UUID() }
                        .buttonStyle(.bordered)
                }.padding(24)
            } else { ProgressView() }
        }
        .task(id: retryID) {
            do {
                store = FundingHistoryStore(service: service, journal: try FundingTransactionJournal())
                failed = false
            } catch { failed = true }
        }
    }
}

struct FundingHistoryView: View {
    let wallet: DeviceWalletSummary
    @ObservedObject var store: FundingHistoryStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var operation: Task<Void, Never>?
    @State private var expandedID: UUID?
    @State private var pendingCancellation: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Label("Arbitrum USDC", systemImage: "dollarsign.circle")
                        .font(.headline)
                    Spacer()
                    Button { refresh() } label: {
                        Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain).foregroundStyle(BSmartColor.brand)
                    .disabled(store.isLoading)
                    .accessibilityLabel("Refresh deposit history".bSmartLocalized)
                }
                if store.isLoading { ProgressView().frame(maxWidth: .infinity, minHeight: 80) }
                else if let message = store.errorMessage {
                    Label(message, systemImage: "exclamationmark.lock")
                        .font(.subheadline).accessibilityIdentifier("deposit.history-error")
                } else if store.didLoad, store.entries.isEmpty {
                    ContentUnavailableView("No deposit records on this device".bSmartLocalized, systemImage: "clock")
                        .accessibilityIdentifier("deposit.history-empty")
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(store.entries) { entry in
                            FundingHistoryRow(entry: entry, expanded: Binding(
                                get: { expandedID == entry.id },
                                set: { expandedID = $0 ? entry.id : nil }
                            ), checkSource: {
                                operation?.cancel()
                                operation = Task { await store.checkSource(id: entry.id, wallet: wallet) }
                            }, checkCrossChain: {
                                operation?.cancel()
                                operation = Task { await store.checkCrossChain(id: entry.id, wallet: wallet) }
                            }) { pendingCancellation = entry.id }
                            Divider().overlay(BSmartColor.line)
                        }
                    }
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 28)
            .frame(maxWidth: 560, alignment: .leading).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .task { await store.refresh(wallet: wallet) }
        .onDisappear { clear() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() } else { clear() }
        }
        .confirmationDialog("Cancel this unsigned review?".bSmartLocalized,
                            isPresented: Binding(get: { pendingCancellation != nil },
                                                 set: { if !$0 { pendingCancellation = nil } })) {
            if let id = pendingCancellation {
                Button("Cancel review".bSmartLocalized, role: .destructive) {
                    operation?.cancel()
                    operation = Task { await store.cancelReview(id: id, wallet: wallet) }
                }
            }
            Button("Keep review".bSmartLocalized, role: .cancel) { pendingCancellation = nil }
        } message: {
            Text("This only closes an unsigned review. It does not cancel a transaction already sent to the network.".bSmartLocalized)
        }
    }

    private func refresh() {
        operation?.cancel()
        operation = Task { await store.refresh(wallet: wallet) }
    }

    private func clear() {
        operation?.cancel()
        operation = nil
        expandedID = nil
        pendingCancellation = nil
        store.clear()
    }
}
