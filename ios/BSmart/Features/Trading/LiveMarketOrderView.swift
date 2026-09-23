import SwiftUI

struct LiveMarketOrderDestination: View {
    @EnvironmentObject private var account: AccountAccessStore
    @EnvironmentObject private var deviceWallet: DeviceWalletStore
    @Environment(\.scenePhase) private var scenePhase
    let coin: String
    let dex: String
    let side: HyperliquidOrderIntent.Side
    var initialAmount = ""
    var initialReduction = false
    var market: HyperliquidPerpMarket? = nil
    var opinionSource: OpinionTradeSource? = nil

    var body: some View {
        Group {
            if case .verified(let wallet) = deviceWallet.state, wallet.canAuthorizeTransactions,
               account.identity?.id == wallet.accountID {
                LiveMarketOrderLoader(wallet: wallet, coin: coin, dex: dex, side: side,
                    initialAmount: initialAmount, initialReduction: initialReduction, market: market, service: account,
                    signer: deviceWallet.signing,
                    attribution: opinionSource.map { NativeOpinionOrderAttribution(source: $0, accountID: wallet.accountID,
                        client: NativeTradeFeedClient(account: account)) },
                    supportsThesis: opinionSource?.supportsThesis == true) {
                    account.configuration.tradingEnabled && account.identity?.id == wallet.accountID
                        && deviceWallet.state == .verified(wallet)
                }.id(wallet.accountID.uuidString + wallet.address + coin + (opinionSource?.opinionID.uuidString ?? ""))
            } else if deviceWallet.isBusy {
                LiveOrderLoadingPanel(reducing: initialReduction)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "wallet.bifold").font(.title)
                    if let error = deviceWallet.errorMessage {
                        Text(error).font(.callout).multilineTextAlignment(.center)
                        Button("Retry".bSmartLocalized) {
                            Task { await deviceWallet.prepare(allowCreation: false) }
                        }.buttonStyle(.borderedProminent)
                    }
                    NavigationLink { TradingWalletView() } label: {
                        Label("Trading wallet".bSmartLocalized, systemImage: "wallet.bifold")
                    }.buttonStyle(.bordered).accessibilityIdentifier("trade.live.wallet")
                }.padding(24)
            }
        }
        .foregroundStyle(BSmartColor.primaryText)
        .background(BSmartColor.ink)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trade.live.screen")
        .task(id: "\(account.walletSessionRevision)-\(scenePhase == .active)") {
            guard scenePhase == .active else { return }
            await deviceWallet.prepare(allowCreation: false)
        }
    }
}

private struct LiveMarketOrderLoader: View {
    let wallet: DeviceWalletSummary
    let coin: String
    let dex: String
    let side: HyperliquidOrderIntent.Side
    let initialAmount: String
    let initialReduction: Bool
    let market: HyperliquidPerpMarket?
    let service: any AccountWalletServicing
    let signer: any TradingWalletSigning
    let attribution: (any OpinionOrderAttributing)?
    let supportsThesis: Bool
    let enabled: () -> Bool
    @State private var store: HyperliquidMarketOrderStore?
    @State private var balances: HyperCoreBalanceStore?
    @State private var failed = false

    var body: some View {
        Group {
            if let store, let balances {
                LiveOrderComposer(wallet: wallet, coin: coin, dex: dex, side: side, initialNotional: initialAmount,
                                  market: market, enabled: enabled(), store: store, balances: balances,
                                  reducing: initialReduction, hasOpinionSource: supportsThesis)
            } else if failed { Text(FundingJournalError.unavailable.localizedDescription).padding(24) }
            else { LiveOrderLoadingPanel(reducing: initialReduction) }
        }.task {
            guard store == nil else { return }
            do {
                let orderStore = try HyperliquidMarketOrderStore(service: service, journal: FundingTransactionJournal(),
                    signer: signer, attribution: attribution, leverageSigner: signer, enabled: enabled)
                balances = HyperCoreBalanceStore(service: service)
                store = orderStore
            }
            catch { failed = true }
        }
    }
}


struct LiveOrderRecordRow: View {
    let record: HyperliquidOrderRecord
    var fills: HyperliquidFillSummary? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(record.order.market.coin).font(.subheadline.weight(.semibold))
                Spacer()
                Text(record.updatedAt, style: .time).font(.caption).foregroundStyle(BSmartColor.secondaryText)
            }
            if record.order.reduceOnly {
                Text((record.order.side == .buy ? "Close short" : "Close long").bSmartLocalized)
                    .font(.caption).foregroundStyle(BSmartColor.secondaryText)
            }
            if case .filled(let fill) = record.acknowledgement {
                Text((fill.isComplete ? "Order filled" : "Partially filled").bSmartLocalized).foregroundStyle(BSmartColor.brand)
                Text(fill.size.wire + " @ " + fill.averagePrice.wire + " USDC").font(.subheadline).monospacedDigit()
            } else if case .rejected(let reason) = record.acknowledgement {
                Text("Order rejected".bSmartLocalized).foregroundStyle(BSmartColor.bear)
                Text(reason).font(.subheadline)
            } else if let status = record.reconciledStatus {
                Text((status.status == "filled" ? "Order filled" : "Order closed").bSmartLocalized)
                    .font(.subheadline)
                Text("#\(status.orderID)").font(.caption.monospaced())
            } else {
                Text("Order status requires verification".bSmartLocalized).font(.subheadline).foregroundStyle(BSmartColor.gold)
            }
        }.accessibilityIdentifier("trade.live.record.\(record.id.uuidString)")
    }
}
