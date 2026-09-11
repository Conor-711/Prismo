import SwiftUI

struct UnifiedAccountSetupView: View {
    let wallet: DeviceWalletSummary
    @EnvironmentObject private var account: AccountAccessStore
    @EnvironmentObject private var device: DeviceWalletStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var store: UnifiedAccountSetupStore?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let store { UnifiedAccountSetupContent(wallet: wallet, store: store) }
            else if let errorMessage { Text(errorMessage).font(.subheadline) }
            else { ProgressView() }
        }.task(id: scenePhase == .background) {
            guard scenePhase != .background else { store?.invalidate(); return }
            do {
                if store == nil {
                    store = try UnifiedAccountSetupStore(service: account, journal: FundingTransactionJournal()) {
                        account.configuration.tradingEnabled && device.state == .verified(wallet)
                    }
                }
                await store?.refresh(wallet: wallet)
            } catch { errorMessage = FundingJournalError.unavailable.localizedDescription }
        }
        .onDisappear { store?.invalidate() }
    }
}

private struct UnifiedAccountSetupContent: View {
    let wallet: DeviceWalletSummary
    @ObservedObject var store: UnifiedAccountSetupStore
    @State private var confirmsMode = false
    @State private var operation: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Trading balance".bSmartLocalized, systemImage: "dollarsign.circle")
                    .font(.headline)
                Spacer()
                if store.isBusy { ProgressView() }
                else { Button { Task { await store.refresh(wallet: wallet) } } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
                }.accessibilityLabel("Refresh".bSmartLocalized) }
            }
            if store.mode == .unifiedAccount {
                Label("Unified USDC enabled".bSmartLocalized, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(BSmartColor.brand)
            } else if let mode = store.mode {
                Text(mode.title).foregroundStyle(BSmartColor.secondaryText)
                Button("Enable unified USDC".bSmartLocalized) { confirmsMode = true }
                    .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                    .disabled(store.isBusy || mode == .portfolioMargin)
                    .accessibilityIdentifier("wallet.enableUnified")
            }
            if let error = store.errorMessage { Text(error).font(.subheadline).foregroundStyle(BSmartColor.bear) }
        }
        .confirmationDialog("Enable unified USDC".bSmartLocalized, isPresented: $confirmsMode, titleVisibility: .visible) {
            Button("Confirm".bSmartLocalized) { operation = Task { await store.enable(wallet: wallet) } }
            Button("Cancel".bSmartLocalized, role: .cancel) {}
        } message: {
            Text("USDC will be shared across your perpetual markets. Losses in one cross-margin position can affect the others. This does not open a trade.".bSmartLocalized)
        }
        .onChange(of: scenePhase) { _, phase in if phase == .background { cancel() } }
        .onDisappear { cancel() }
    }
    private func cancel() { operation?.cancel(); operation = nil; store.invalidate(); confirmsMode = false }
}
