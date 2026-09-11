import SwiftUI

struct ArbitrumReceiveContent: View {
    let context: ArbitrumReceiveContext
    let address: WalletReceiveAddress?
    let isLoading: Bool
    let expired: Bool
    let copied: Bool
    let errorMessage: String?
    @Binding var networkConfirmed: Bool
    let verify: () -> Void
    let copy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 12) {
                Image(systemName: "dollarsign.circle.fill").font(.system(size: 36)).foregroundStyle(BSmartColor.sky)
                VStack(alignment: .leading, spacing: 4) {
                    Text("USDC").font(.title2.bold())
                    Text("Arbitrum One").font(.subheadline.weight(.semibold)).foregroundStyle(BSmartColor.sky)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Label("Only native USDC on Arbitrum One. Do not send USDC.e or use another network.".bSmartLocalized,
                      systemImage: "exclamationmark.triangle")
                Text("Choose Arbitrum One in the sending wallet or exchange. The QR code does not select a network.".bSmartLocalized)
            }.font(.subheadline).fixedSize(horizontal: false, vertical: true)

            if !context.depositsEnabled {
                Label("Deposits are not open yet".bSmartLocalized, systemImage: "lock.fill").font(.headline)
                    .accessibilityIdentifier("wallet.receive-locked")
            } else if context.wallet?.canAuthorizeTransactions != true {
                Label("Unlock your wallet to continue.".bSmartLocalized,
                      systemImage: "lock.shield").font(.headline)
                    .accessibilityIdentifier("wallet.receive-wallet-required")
            } else {
                Toggle("I will send native USDC on Arbitrum One.".bSmartLocalized, isOn: $networkConfirmed)
                    .font(.subheadline.weight(.medium)).tint(BSmartColor.brand)
                    .accessibilityIdentifier("wallet.receive-confirm-network")
                if let address, context.eligible {
                    VStack(spacing: 18) {
                        WalletReceiveQRCodeView(address: address).id(address)
                        WalletReceiveAddressText(address: address)
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("wallet.receive-address")
                        action(copied ? "Copied" : "Copy address", icon: copied ? "checkmark" : "doc.on.doc", perform: copy)
                            .accessibilityIdentifier("wallet.receive-copy")
                    }.frame(maxWidth: .infinity)
                } else {
                    if expired {
                        Text("Address check expired. Verify again.".bSmartLocalized)
                            .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                    }
                    action(isLoading ? "Verifying wallet" : "Verify receiving address", icon: "qrcode", perform: verify)
                        .disabled(!context.eligible || isLoading)
                        .opacity(context.eligible ? 1 : 0.45)
                        .accessibilityIdentifier("wallet.receive-verify")
                }
            }
            if let errorMessage {
                Text(errorMessage).font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("wallet.receive-error")
            }
            Divider().overlay(BSmartColor.line)
            VStack(alignment: .leading, spacing: 16) {
                Label("USDC in your wallet is not yet a Hyperliquid trading balance.".bSmartLocalized,
                      systemImage: "arrow.right.arrow.left")
                Label("Moving USDC into Hyperliquid requires ETH on Arbitrum for network fees.".bSmartLocalized,
                      systemImage: "fuelpump")
            }.font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func action(_ title: String, icon: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack(spacing: 10) {
                if isLoading { ProgressView().tint(BSmartColor.onAccent) }
                else { Image(systemName: icon) }
                Text(title.bSmartLocalized).fixedSize(horizontal: false, vertical: true)
            }
            .font(.subheadline.weight(.semibold)).padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(BSmartColor.onAccent)
            .background(BSmartColor.brand, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain)
    }
}
