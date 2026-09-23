import SwiftUI

struct AcrossWithdrawalView: View {
    @EnvironmentObject private var deviceWallet: DeviceWalletStore
    let wallet: DeviceWalletSummary
    @ObservedObject var store: AcrossWithdrawalStore
    let enabled: Bool
    let walletReady: Bool
    @Binding var amount: String
    @Binding var recipient: String
    @State private var acknowledged = false
    @State private var operation: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase
    private enum Field: Hashable { case recipient, amount }
    @FocusState private var focused: Field?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Image("FundingAsset_USDC")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("USDC").font(.title2.bold())
                        Text("Trading account".bSmartLocalized)
                            .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Network".bSmartLocalized)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(BSmartColor.secondaryText)
                    HStack(spacing: 8) {
                        Image("FundingChain_Arbitrum")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .accessibilityHidden(true)
                        Text("Arbitrum One").font(.subheadline.weight(.semibold))
                    }
                    .frame(height: 50)
                    .accessibilityIdentifier("withdraw.network.arbitrum")
                }

                if !walletReady {
                    HStack {
                        Label("Reconnect wallet to withdraw".bSmartLocalized, systemImage: "lock.shield")
                            .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                        Spacer()
                        if scenePhase == .active && !deviceWallet.isBusy {
                            Button("Retry".bSmartLocalized) { Task { await deviceWallet.prepare() } }
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                } else if !enabled {
                    Label("Withdrawals are not available yet.".bSmartLocalized, systemImage: "lock.shield")
                        .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                }

                HStack {
                    Text("Withdrawable".bSmartLocalized).foregroundStyle(BSmartColor.secondaryText)
                    Spacer()
                    Text(store.availableAmount.map { $0 + " USDC" } ?? "--")
                        .fontWeight(.semibold).monospacedDigit()
                    Button {
                        operation = Task { await store.load(wallet: wallet) }
                    } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }
                        .accessibilityLabel("Refresh".bSmartLocalized).disabled(store.isBusy)
                }.font(.subheadline)

                if let pending = store.pending, store.quote == nil {
                    Label(pending.statusTitle.bSmartLocalized, systemImage: "clock.arrow.circlepath")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(BSmartColor.gold)
                    Text("Do not retry while this withdrawal is being checked.".bSmartLocalized)
                        .font(.footnote).foregroundStyle(BSmartColor.secondaryText)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Recipient address".bSmartLocalized).font(.subheadline.weight(.medium))
                    TextField("0x…", text: $recipient)
                        .font(.body.monospaced()).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .focused($focused, equals: .recipient).padding(14)
                        .bSmartInputSurface(focused: focused == .recipient)
                        .accessibilityIdentifier("withdraw.recipient")
                    HStack {
                        Button("Use my wallet".bSmartLocalized) { recipient = wallet.address }
                        Spacer()
                        Button {
                            guard let pasted = UIPasteboard.general.string?
                                .trimmingCharacters(in: .whitespacesAndNewlines), !pasted.isEmpty else { return }
                            recipient = pasted
                        } label: {
                            Label("Paste".bSmartLocalized, systemImage: "doc.on.clipboard")
                        }
                        .accessibilityIdentifier("withdraw.recipient.paste")
                    }
                    .font(.subheadline)
                    .foregroundStyle(BSmartColor.brand)
                    .frame(minHeight: 44)
                }.disabled(store.isBusy && store.hasLoaded || store.quote != nil || store.pending != nil)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Amount".bSmartLocalized).font(.subheadline.weight(.medium))
                    HStack {
                        TextField("0", text: $amount).keyboardType(.decimalPad).focused($focused, equals: .amount)
                            .font(.system(size: 30, weight: .semibold)).monospacedDigit()
                            .accessibilityIdentifier("withdraw.amount")
                        Text("USDC").font(.headline)
                        Button("Max".bSmartLocalized) { amount = store.availableAmount ?? "" }
                            .font(.subheadline.weight(.semibold)).frame(minWidth: 44, minHeight: 44)
                            .background(BSmartColor.brand.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                            .disabled(store.availableAmount == nil || store.availableAmount == "0")
                    }.padding(14).bSmartInputSurface(focused: focused == .amount)
                }.disabled(store.isBusy && store.hasLoaded || store.quote != nil || store.pending != nil)

                if let quote = store.quote {
                    Divider().overlay(BSmartColor.line)
                    Text("Review withdrawal".bSmartLocalized).font(.headline)
                    metric("Withdrawal amount", amount + " USDC")
                    metric("Expected arrival", usdc(quote.record.expectedOutputUnits))
                    metric("Minimum arrival", usdc(quote.record.minOutputUnits))
                    if let fee = quote.record.submissionFeeUnits,
                       let decimals = quote.record.submissionFeeDecimals,
                       let value = AcrossWithdrawalRecord.formatted(fee, decimals: decimals) {
                        metric("Across submission fee", value + " " + (quote.record.submissionFeeSymbol ?? "USDC"))
                    }
                    Text("If delivery fails, a refund may arrive on HyperEVM instead of your trading balance.".bSmartLocalized)
                        .font(.footnote).foregroundStyle(BSmartColor.secondaryText)
                    Toggle("I confirm the Arbitrum address, quoted amount and refund destination.".bSmartLocalized,
                           isOn: $acknowledged).font(.subheadline).disabled(store.isBusy)
                    Button("Change details".bSmartLocalized) {
                        acknowledged = false
                        operation = Task { await store.cancelReview(wallet: wallet) }
                    }.font(.subheadline).foregroundStyle(BSmartColor.brand).disabled(store.isBusy)
                }

                if let error = store.errorMessage {
                    Text(error).font(.subheadline).foregroundStyle(BSmartColor.bear)
                        .accessibilityIdentifier("withdraw.error")
                }

                Button {
                    focused = nil
                    operation = Task {
                        if store.quote == nil {
                            await store.review(amount: amount,
                                               recipient: recipient.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                                               wallet: wallet)
                        } else { await store.confirm(wallet: wallet) }
                    }
                } label: {
                    HStack {
                        if store.isBusy { ProgressView() }
                        else { Image(systemName: store.quote == nil ? "arrow.up.right" : "lock.shield") }
                        Text((store.quote == nil ? "Get withdrawal quote" : "Confirm withdrawal").bSmartLocalized)
                    }.font(.headline).frame(maxWidth: .infinity, minHeight: 48).bSmartActionSurface()
                }.buttonStyle(.plain)
                    .disabled(!enabled || !walletReady || store.isBusy || store.pending != nil && store.quote == nil ||
                              store.quote != nil && !acknowledged || scenePhase != .active ||
                              store.quote == nil && (!TradingWalletChallenge.validAddress(recipient) ||
                                                      (Decimal(string: amount) ?? 0) <= 0))
                    .accessibilityIdentifier("withdraw.confirm")

                if !store.history.isEmpty {
                    Divider().overlay(BSmartColor.line)
                    Text("Withdrawal history".bSmartLocalized).font(.headline)
                    ForEach(store.history) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.statusTitle.bSmartLocalized).font(.subheadline.weight(.medium))
                                Text(item.recipient).font(.caption.monospaced()).lineLimit(1)
                                    .truncationMode(.middle).foregroundStyle(BSmartColor.secondaryText)
                            }
                            Spacer()
                            Text(AcrossWithdrawalRecord.formatted(item.amountUnits, decimals: 8) ?? "--")
                                .font(.subheadline.monospacedDigit())
                        }.padding(.vertical, 8)
                        Divider().overlay(BSmartColor.line)
                    }
                }
                acrossAttribution
            }.padding(20)
        }
        .task(id: walletReady && scenePhase == .active) {
            guard walletReady, scenePhase == .active, !store.hasLoaded else { return }
            await store.load(wallet: wallet)
        }
        .background(BSmartColor.ink).foregroundStyle(BSmartColor.primaryText)
        .accessibilityIdentifier("withdraw.screen")
    }

    private func usdc(_ units: String) -> String {
        (AcrossWithdrawalRecord.formatted(units, decimals: 6) ?? "--") + " USDC"
    }

    private var acrossAttribution: some View {
        Link(destination: URL(string: "https://docs.across.to/introduction/hypercore-withdrawals")!) {
            HStack(spacing: 8) {
                Image("FundingProvider_Across")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .accessibilityHidden(true)
                Text("Powered by Across".bSmartLocalized)
                Image(systemName: "arrow.up.right")
                    .font(.caption2)
                    .accessibilityHidden(true)
            }
            .font(.footnote)
            .foregroundStyle(BSmartColor.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .accessibilityIdentifier("withdraw.across")
    }

    private func metric(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title.bSmartLocalized).foregroundStyle(BSmartColor.secondaryText)
            Spacer()
            Text(value).fontWeight(.semibold).monospacedDigit()
        }.font(.subheadline)
    }
}
