import SwiftUI

struct ArbitrumReceiveView: View {
    @EnvironmentObject private var account: AccountAccessStore
    @EnvironmentObject private var wallet: DeviceWalletStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var receive: ArbitrumReceiveStore
    @State private var networkConfirmed = false
    @State private var copied = false
    @State private var request: Task<Void, Never>?

    init(service: AccountWalletServicing) {
        _receive = StateObject(wrappedValue: ArbitrumReceiveStore(service: service))
    }

    private var context: ArbitrumReceiveContext {
        let local: DeviceWalletSummary?
        if case .verified(let summary) = wallet.state { local = summary } else { local = nil }
        return .init(wallet: local, depositsEnabled: account.configuration.depositsEnabled && scenePhase == .active,
                     networkConfirmed: networkConfirmed)
    }

    var body: some View {
        ScrollView {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let address = receive.currentAddress(context: context)
                ArbitrumReceiveContent(context: context, address: address, isLoading: receive.isLoading,
                    expired: receive.hasChecked && address == nil, copied: copied,
                    errorMessage: receive.errorMessage, networkConfirmed: $networkConfirmed,
                    verify: verify, copy: copy)
                .padding(24).frame(maxWidth: 520).frame(maxWidth: .infinity)
            }
        }
        .background(BSmartColor.ink).foregroundStyle(BSmartColor.primaryText)
        .navigationTitle("Receive USDC".bSmartLocalized).navigationBarTitleDisplayMode(.inline)
        .onChange(of: context) { _, _ in clear() }
        .onChange(of: account.identity?.id) { _, _ in networkConfirmed = false; clear() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { networkConfirmed = false; clear() }
        }
        .onDisappear { networkConfirmed = false; clear() }
        .accessibilityIdentifier("wallet.receive-screen")
        .bSmartPage()
    }

    private func verify() {
        request?.cancel(); copied = false
        let captured = context
        request = Task { await receive.refresh(context: captured) }
    }

    private func copy() {
        guard let address = receive.currentAddress(context: context) else { clear(); return }
        WalletReceiveClipboard.copy(address)
        copied = true
    }

    private func clear() {
        request?.cancel(); request = nil; receive.clear(); copied = false
    }
}
