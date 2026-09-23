import SwiftUI

struct UnifiedAccountSetupView: View {
    let wallet: DeviceWalletSummary
    var compact = false
    var onEnabled: (() -> Void)? = nil
    @EnvironmentObject private var account: AccountAccessStore
    @EnvironmentObject private var device: DeviceWalletStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var store: UnifiedAccountSetupStore?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let store { UnifiedAccountSetupContent(wallet: wallet, store: store, compact: compact, onEnabled: onEnabled) }
            else if let errorMessage { Text(errorMessage).font(.subheadline) }
            else { ProgressView() }
        }.task(id: scenePhase == .background) {
            guard scenePhase != .background else { store?.invalidate(); return }
            do {
                if store == nil {
                    store = try UnifiedAccountSetupStore(service: account, journal: FundingTransactionJournal(), signer: device.signing) {
                        account.configuration.tradingEnabled && device.state == .verified(wallet)
                    }
                }
                await store?.prepare(wallet: wallet)
            } catch { errorMessage = FundingJournalError.unavailable.localizedDescription }
        }
        .onDisappear { store?.invalidate() }
    }
}

private struct UnifiedAccountSetupContent: View {
    let wallet: DeviceWalletSummary
    @ObservedObject var store: UnifiedAccountSetupStore
    var compact = false
    var onEnabled: (() -> Void)? = nil
    @State private var operation: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !compact { HStack {
                Label("Trading balance".bSmartLocalized, systemImage: "dollarsign.circle")
                    .font(.headline)
                Spacer()
                if store.isBusy { ProgressView() }
                else { Button { Task { await store.refresh(wallet: wallet) } } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
                }.accessibilityLabel("Refresh".bSmartLocalized) }
            } }
            if compact && store.isBusy { ProgressView().frame(maxWidth: .infinity) }
            if store.mode == .unifiedAccount {
                Label("Unified USDC enabled".bSmartLocalized, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(BSmartColor.brand)
            } else if let mode = store.mode {
                if !compact { Text(mode.title).foregroundStyle(BSmartColor.secondaryText) }
                Button("Retry".bSmartLocalized) { operation = Task { await store.enable(wallet: wallet) } }
                    .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                    .disabled(store.isBusy || mode == .portfolioMargin)
                    .accessibilityIdentifier("wallet.enableUnified")
            }
            if let error = store.errorMessage { Text(error).font(.subheadline).foregroundStyle(BSmartColor.bear) }
        }
        .onChange(of: store.mode, initial: true) { _, mode in
            if mode == .unifiedAccount { onEnabled?() }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .background { cancel() } }
        .onDisappear { cancel() }
    }
    private func cancel() { operation?.cancel(); operation = nil; store.invalidate() }
}
