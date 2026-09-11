import SwiftUI

struct DeviceWalletPanel: View {
    @EnvironmentObject private var wallet: DeviceWalletStore
    @EnvironmentObject private var account: AccountAccessStore
    @State private var showsRecovery = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            switch wallet.state {
            case .locked:
                Label("Device wallet".bSmartLocalized, systemImage: "lock.shield")
                    .font(.headline)
                action("Set up / Unlock wallet", icon: "lock.open") { Task { await wallet.prepare() } }
                    .accessibilityIdentifier("wallet.unlock")
            case .loading:
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Verifying wallet".bSmartLocalized).font(.headline)
                }.frame(minHeight: 48)
            case .recoveryRequired:
                Label("Restore your wallet".bSmartLocalized, systemImage: "arrow.clockwise")
                    .font(.headline)
                Text("Restore the wallet already linked to this account.".bSmartLocalized)
                    .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                action("Restore wallet", icon: "key") { showsRecovery = true }
            case .verified(let local):
                HStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill").font(.title2).foregroundStyle(BSmartColor.brand)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Device wallet".bSmartLocalized).font(.headline)
                        Text(String(local.address.prefix(6)) + "..." + String(local.address.suffix(4)))
                            .font(.subheadline.monospaced()).foregroundStyle(BSmartColor.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(BSmartColor.brand)
                }
                if DeviceWalletBackupPolicy.current == .required {
                    Label((local.recoveryVerified ? "Recovery verified" : "Back up before depositing").bSmartLocalized,
                          systemImage: local.recoveryVerified ? "checkmark.shield" : "exclamationmark.shield")
                        .font(.subheadline)
                        .foregroundStyle(local.recoveryVerified ? BSmartColor.brand : BSmartColor.secondaryText)
                    action(local.recoveryVerified ? "View recovery phrase" : "Back up wallet", icon: "key") {
                        showsRecovery = true
                    }
                    .accessibilityIdentifier("wallet.backup")
                } else if !local.recoveryVerified {
                    Label("No backup is required for this internal build. If the device key is lost, funds cannot be recovered with Google login.".bSmartLocalized,
                          systemImage: "exclamationmark.shield")
                        .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("wallet.device-only-warning")
                }
                NavigationLink {
                    ArbitrumReceiveView(service: account)
                } label: {
                    HStack {
                        Label("Receive USDC".bSmartLocalized, systemImage: "qrcode")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }
                    .font(.subheadline.weight(.semibold)).frame(minHeight: 48)
                    .foregroundStyle(BSmartColor.primaryText)
                }
                .accessibilityIdentifier("wallet.receive")
                NavigationLink { CCTPTransferDestination() } label: {
                    HStack {
                        Label("Transfer to Hyperliquid".bSmartLocalized, systemImage: "arrow.right.arrow.left")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }.font(.subheadline.weight(.semibold)).frame(minHeight: 48)
                        .foregroundStyle(BSmartColor.primaryText)
                }
                .accessibilityIdentifier("wallet.transfer")
                NavigationLink { HyperliquidWithdrawalDestination() } label: {
                    HStack {
                        Label("Withdraw USDC".bSmartLocalized, systemImage: "arrow.up.right")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }.font(.subheadline.weight(.semibold)).frame(minHeight: 48)
                        .foregroundStyle(BSmartColor.primaryText)
                }
                .accessibilityIdentifier("wallet.withdraw")
                if DeviceWalletBackupPolicy.current == .optionalForInternalTesting {
                    DisclosureGroup("Optional wallet backup".bSmartLocalized) {
                        action("View recovery phrase", icon: "key") { showsRecovery = true }
                            .accessibilityIdentifier("wallet.backup")
                    }
                    .font(.subheadline).tint(BSmartColor.secondaryText)
                    .accessibilityIdentifier("wallet.optional-backup")
                }
                Divider().overlay(BSmartColor.line)
                ArbitrumWalletBalanceView(wallet: local)
                Divider().overlay(BSmartColor.line)
                HyperCoreBalanceView(wallet: local, service: account)
                    .id(local.accountID.uuidString + local.address)
            }
            if let message = wallet.errorMessage {
                Text(message).font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                    .accessibilityIdentifier("wallet.error")
            }
        }
        .disabled(wallet.isBusy)
        .fullScreenCover(isPresented: $showsRecovery) {
            NavigationStack { DeviceWalletRecoveryView() }
        }
        .accessibilityIdentifier("wallet.panel")
    }

    private func action(_ title: String, icon: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Label(title.bSmartLocalized, systemImage: icon)
                .font(.system(.subheadline, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(BSmartColor.brand)
                .background(BSmartColor.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(BSmartColor.brand.opacity(0.4), lineWidth: 1))
        }.buttonStyle(.plain)
    }
}
