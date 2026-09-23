import SwiftUI

struct ManagedDepositView: View {
    @EnvironmentObject private var account: AccountAccessStore
    @EnvironmentObject private var wallet: DeviceWalletStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var funding: ManagedFundingStore
    @State private var network: ManagedFundingNetwork = .monad
    @State private var copied = false
    @State private var reloadID = UUID()
    @ScaledMetric(relativeTo: .headline) private var tabHeight = 50.0
    private let showsHistory: Bool

    init(account: AccountAccessStore, showsHistory: Bool = true) {
        self.showsHistory = showsHistory
        _funding = StateObject(wrappedValue: ManagedFundingStore(service: ManagedFundingClient(account: account)))
    }

    private var local: DeviceWalletSummary? {
        guard scenePhase == .active, account.configuration.depositsEnabled,
              case .verified(let value) = wallet.state,
              value.accountID == account.identity?.id, value.canAuthorizeTransactions else { return nil }
        return value
    }
    private var contextID: String {
        "\(local?.accountID.uuidString ?? ""):\(local?.address ?? ""):\(account.walletSessionRevision)"
    }
    private var readyAddress: WalletReceiveAddress? {
        guard let deposit = funding.address,
              local?.address == deposit.recipient,
              deposit.network == network else { return nil }
        return try? WalletReceiveAddress(owner: deposit.depositAddress)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 12) {
                    Image("FundingAsset_USDC")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("USDC").font(.title2.bold())
                        Text("Trading account".bSmartLocalized).font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                    }
                }
                networkTabs
                if let address = readyAddress {
                    WalletReceiveQRCodeView(address: address).frame(maxWidth: .infinity)
                    WalletReceiveAddressText(address: address).frame(maxWidth: .infinity)
                    Button {
                        guard readyAddress != nil else { return }
                        WalletReceiveClipboard.copy(address); copied = true
                    } label: {
                        Label((copied ? "Copied" : "Copy address").bSmartLocalized,
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }.buttonStyle(.borderedProminent).tint(BSmartColor.brand).foregroundStyle(BSmartColor.onAccent)
                    Text("Send only %@ on %@ to this deposit address. Refunds return to your account wallet on the same network."
                        .bSmartLocalized(network.depositAsset.bSmartLocalized, network.title))
                        .font(.footnote).foregroundStyle(BSmartColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if showsHistory {
                        DisclosureGroup("Deposit fees".bSmartLocalized) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Network and routing costs are deducted when funds arrive. Small deposits have a higher relative cost; deposits that cannot cover fees may be refunded minus gas.".bSmartLocalized)
                                Text("New HyperCore accounts incur a one-time activation fee of 1 USDC, in addition to route costs. External wallet or exchange sending fees are separate.".bSmartLocalized)
                            }.font(.footnote).foregroundStyle(BSmartColor.secondaryText)
                                .fixedSize(horizontal: false, vertical: true).padding(.top, 12)
                        }.font(.subheadline).tint(BSmartColor.brand)
                    } else {
                        Text("Network and routing costs are deducted when funds arrive. Small deposits have a higher relative cost; deposits that cannot cover fees may be refunded minus gas.".bSmartLocalized)
                            .font(.footnote).foregroundStyle(BSmartColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if local != nil, funding.errorMessage == nil {
                    ProgressView("Getting deposit address".bSmartLocalized)
                        .tint(BSmartColor.brand).frame(maxWidth: .infinity, minHeight: 220)
                }
                if local == nil, scenePhase == .active {
                    Text((account.configuration.depositsEnabled
                          ? "Unlock your wallet to continue." : "Deposits are not open yet").bSmartLocalized)
                        .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                }
                if let error = funding.errorMessage {
                    Text(error).font(.subheadline).foregroundStyle(BSmartColor.bear)
                    Button("Try again".bSmartLocalized) {
                        reloadID = UUID()
                    }
                }
                if showsHistory {
                    Divider().overlay(BSmartColor.line)
                    ManagedDepositHistory(deposits: funding.deposits, error: funding.historyError)
                    NavigationLink { CCTPTransferDestination() } label: {
                        AccountActionRow(title: "Existing wallet funds", symbol: "wallet.bifold")
                    }
                }
                if readyAddress != nil { relayAttribution }
            }.padding(24).frame(maxWidth: 520).frame(maxWidth: .infinity)
        }
        .navigationTitle("Deposit".bSmartLocalized).navigationBarTitleDisplayMode(.inline)
        .background(BSmartColor.ink).foregroundStyle(BSmartColor.primaryText)
        .task(id: "\(contextID):\(network.rawValue):\(reloadID)") {
            funding.clear(); copied = false
            guard let local else { return }
            let selectedNetwork = network
            await funding.load(wallet: local)
            guard !Task.isCancelled else { return }
            await funding.prepare(wallet: local, network: selectedNetwork)
            if showsHistory {
                while !Task.isCancelled {
                    await funding.refreshHistory(wallet: local)
                    do { try await Task.sleep(for: .seconds(15)) } catch { return }
                }
            }
        }
        .onDisappear { funding.clear() }
        .accessibilityIdentifier("funding.deposit.screen")
        .bSmartPage()
    }

    private var relayAttribution: some View {
        Link(destination: URL(string: "https://docs.relay.link/features/deposit-addresses")!) {
            HStack(spacing: 8) {
                Image("FundingProvider_Relay")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .accessibilityHidden(true)
                Text("Powered by Relay".bSmartLocalized)
                Image(systemName: "arrow.up.right")
                    .font(.caption2)
                    .accessibilityHidden(true)
            }
            .font(.footnote)
            .foregroundStyle(BSmartColor.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .accessibilityIdentifier("funding.deposit.relay")
    }

    private var networkTabs: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Network".bSmartLocalized)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(BSmartColor.secondaryText)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 26) {
                        ForEach(ManagedFundingNetwork.allCases) { value in
                            Button {
                                withAnimation(reduceMotion ? nil : BSmartMotion.quick) { network = value }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(value.logoAsset)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 24, height: 24)
                                    Text(value.title)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                                .foregroundStyle(network == value ? BSmartColor.primaryText : BSmartColor.tertiaryText)
                                .padding(.horizontal, 4)
                                .frame(height: tabHeight)
                                .contentShape(Rectangle())
                                .overlay(alignment: .bottom) {
                                    if network == value {
                                        Capsule().fill(BSmartColor.brand).frame(height: 3)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .id(value)
                            .accessibilityAddTraits(network == value ? .isSelected : [])
                            .accessibilityIdentifier("funding.network.\(value.rawValue)")
                        }
                    }
                    .padding(.horizontal, 1)
                }
                .frame(height: tabHeight)
                .onChange(of: network) { _, selected in
                    withAnimation(reduceMotion ? nil : BSmartMotion.quick) { proxy.scrollTo(selected, anchor: .center) }
                }
            }
        }
    }

}

private struct ManagedDepositHistory: View {
    let deposits: [ManagedFundingDeposit]
    let error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent deposits".bSmartLocalized).font(.headline)
            if let error { Text(error).font(.subheadline).foregroundStyle(BSmartColor.secondaryText) }
            ForEach(deposits) { deposit in
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(deposit.title.bSmartLocalized).font(.subheadline.weight(.medium))
                        Text(deposit.createdAt, style: .date).font(.caption).foregroundStyle(BSmartColor.secondaryText)
                    }
                    Spacer()
                    if let amount = deposit.amount { Text("$" + amount).font(.subheadline.weight(.semibold)) }
                }
            }
        }
    }
}
