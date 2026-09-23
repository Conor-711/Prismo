import SwiftUI

struct CCTPTransferContent: View {
    let display: CCTPTransferDisplay
    let isBusy: Bool
    let now: Date
    let errorMessage: String?
    @Binding var amount: String
    var amountFocused: FocusState<Bool>.Binding
    let primary: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                Text("Arbitrum").fontWeight(.semibold)
                Image(systemName: "arrow.right").foregroundStyle(BSmartColor.secondaryText)
                Text("Hyperliquid").fontWeight(.semibold)
            }.font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle()).onTapGesture { amountFocused.wrappedValue = false }
            if display.phase == .amount {
                HStack(spacing: 12) {
                    TextField("Amount".bSmartLocalized, text: $amount)
                        .keyboardType(.decimalPad).focused(amountFocused)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(.title3.weight(.semibold)).monospacedDigit()
                        .accessibilityIdentifier("deposit.transfer-amount")
                        .onChange(of: amount) { _, value in if value.count > 32 { amount = String(value.prefix(32)) } }
                    Text("USDC").font(.subheadline.weight(.semibold))
                }.padding(16).background(BSmartColor.surface, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(BSmartColor.line))
                Text("Arbitrum USDC · ETH for network fees".bSmartLocalized)
                    .font(.caption).foregroundStyle(BSmartColor.secondaryText)
                    .onTapGesture { amountFocused.wrappedValue = false }
            }
            if let details = display.details {
                Text(ArbitrumDepositPolicy.formatted(details.amount) + " USDC")
                    .font(.title2.bold()).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                row("Maximum transfer fee", value: usdc(details.maximumTransferFee))
                if details.maximumTransferFee < details.amount {
                    row("Net at maximum CCTP fee", value: usdc(details.amount - details.maximumTransferFee))
                }
                if let fee = details.maximumNetworkFee {
                    row("Maximum network fee", value: fee.formatted(decimals: 18) + " ETH")
                }
                Text("The final credited amount may include an account activation fee.".bSmartLocalized)
                    .font(.caption).foregroundStyle(BSmartColor.secondaryText)
                Divider().overlay(BSmartColor.line)
                Text("Receiving wallet".bSmartLocalized).font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                if let address = try? WalletReceiveAddress(owner: details.owner) {
                    WalletReceiveAddressText(address: address)
                }
            }
            if let entry = display.entry, display.phase == .recorded || display.phase == .signed {
                Label(entry.stage.title.bSmartLocalized, systemImage: entry.stage.symbol)
                    .font(.headline).foregroundStyle(BSmartColor.gold)
                if let notice = entry.stage.notice {
                    Text(notice.bSmartLocalized).font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                }
            }
            if let errorMessage {
                Text(errorMessage).font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                    .accessibilityIdentifier("deposit.transfer-error")
            }
            if isBusy { ProgressView().frame(maxWidth: .infinity, minHeight: 48) }
            else if let label = display.phase.action {
                if [.authorization, .networkFee, .signed].contains(display.phase) && !display.canConfirm(at: now) {
                    Label("Deposit confirmation expired. Review the details again.".bSmartLocalized,
                          systemImage: "clock.badge.exclamationmark").font(.subheadline)
                }
                Button(action: primary) {
                    Label((display.phase == .networkFee && !display.canConfirm(at: now) ? "Refresh" : label).bSmartLocalized,
                          systemImage: display.phase == .networkFee ? "arrow.up.right" : "arrow.right")
                        .font(.subheadline.weight(.semibold)).padding(14)
                        .frame(maxWidth: .infinity, minHeight: 48).bSmartActionSurface()
                }.buttonStyle(.plain)
                    .disabled(display.phase == .amount ? amount.isEmpty
                              : [.authorization, .signed].contains(display.phase) && !display.canConfirm(at: now))
                    .accessibilityIdentifier("deposit.transfer-primary")
            }
            if !isBusy, display.phase == .authorization || display.phase == .networkFee {
                Button(action: cancel) {
                    Label("Cancel review".bSmartLocalized, systemImage: "xmark.circle")
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.plain).foregroundStyle(BSmartColor.secondaryText)
                    .accessibilityIdentifier("deposit.transfer-cancel")
            }
        }.fixedSize(horizontal: false, vertical: true)
    }

    private func usdc(_ amount: UInt64) -> String { ArbitrumDepositPolicy.formatted(amount) + " USDC" }

    private func row(_ title: String, value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title.bSmartLocalized).foregroundStyle(BSmartColor.secondaryText).fixedSize()
                Spacer(minLength: 0)
                Text(value).fontWeight(.semibold).monospacedDigit().fixedSize()
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(title.bSmartLocalized).foregroundStyle(BSmartColor.secondaryText)
                Text(value).fontWeight(.semibold).monospacedDigit()
            }
        }.font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension CCTPTransferDisplay.Phase {
    var title: String {
        switch self {
        case .amount: "Transfer USDC"
        case .checking: "Checking wallet and balance"
        case .authorization: "Review USDC authorization"
        case .authorizing: "Authorizing USDC"
        case .preflight: "Checking network fee"
        case .networkFee: "Review network transaction"
        case .signing: "Signing transaction"
        case .signed: "Ready to submit"
        case .submitting: "Checking and submitting"
        case .recorded: "Transfer recorded"
        case .recovery: "Review deposit history"
        }
    }
    var action: String? {
        switch self {
        case .amount: "Continue"
        case .authorization: "Authorize USDC"
        case .networkFee: "Confirm transfer"
        case .signed: "Submit transaction"
        case .recovery: "Try again"
        default: nil
        }
    }
}
