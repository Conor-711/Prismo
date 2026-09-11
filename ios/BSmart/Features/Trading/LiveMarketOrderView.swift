import SwiftUI

struct LiveMarketOrderDestination: View {
    @EnvironmentObject private var account: AccountAccessStore
    @EnvironmentObject private var deviceWallet: DeviceWalletStore
    let coin: String
    let dex: String
    let side: HyperliquidOrderIntent.Side
    var initialAmount = ""
    var initialReduction = false
    var market: HyperliquidPerpMarket? = nil

    var body: some View {
        Group {
            if case .verified(let wallet) = deviceWallet.state, wallet.canAuthorizeTransactions,
               account.identity?.id == wallet.accountID {
                LiveMarketOrderLoader(wallet: wallet, coin: coin, dex: dex, side: side,
                    initialAmount: initialAmount, initialReduction: initialReduction, market: market, service: account) {
                    account.configuration.tradingEnabled && account.identity?.id == wallet.accountID
                        && deviceWallet.state == .verified(wallet)
                }.id(wallet.accountID.uuidString + wallet.address + coin)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "lock.shield").font(.title)
                    Text("Unlock your wallet to continue.".bSmartLocalized).multilineTextAlignment(.center)
                    NavigationLink { TradingWalletView() } label: {
                        Label("Device wallet".bSmartLocalized, systemImage: "wallet.bifold")
                    }.buttonStyle(.bordered).accessibilityIdentifier("trade.live.wallet")
                }.padding(24)
            }
        }
        .foregroundStyle(BSmartColor.primaryText)
        .background(BSmartColor.ink)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trade.live.screen")
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
    let enabled: () -> Bool
    @State private var store: HyperliquidMarketOrderStore?
    @State private var failed = false

    var body: some View {
        Group {
            if let store {
                LiveMarketOrderView(wallet: wallet, coin: coin, dex: dex, initialSide: side,
                                    initialAmount: initialAmount, store: store, enabled: enabled(), initialReduction: initialReduction,
                                    market: market)
            } else if failed { Text(FundingJournalError.unavailable.localizedDescription).padding(24) }
            else { ProgressView() }
        }.task {
            guard store == nil else { return }
            do { store = try .init(service: service, journal: FundingTransactionJournal(), enabled: enabled) }
            catch { failed = true }
        }
    }
}

struct LiveMarketOrderView: View {
    let wallet: DeviceWalletSummary
    let coin: String
    let dex: String
    @ObservedObject var store: HyperliquidMarketOrderStore
    let enabled: Bool
    let market: HyperliquidPerpMarket?
    @State private var amount: TradeAmountInput
    @State private var side: HyperliquidOrderIntent.Side
    @State private var slippage: UInt64 = 50
    @State private var reducing: Bool
    @State private var reductionPercent = 100
    @State private var operation: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    init(wallet: DeviceWalletSummary, coin: String, dex: String, initialSide: HyperliquidOrderIntent.Side,
         initialAmount: String, store: HyperliquidMarketOrderStore, enabled: Bool, initialReduction: Bool = false,
         market: HyperliquidPerpMarket? = nil) {
        self.wallet = wallet; self.coin = coin; self.dex = dex; self.store = store; self.enabled = enabled
        self.market = market
        _amount = State(initialValue: TradeAmountInput(text: initialAmount, fractionDigits: 6)); _side = State(initialValue: initialSide)
        _reducing = State(initialValue: initialReduction)
    }

    var body: some View {
        VStack(spacing: 12) {
            ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !enabled {
                    Label("Live trading is not open yet.".bSmartLocalized, systemImage: "lock.shield")
                        .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                }
                orderControls
                if reducing {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Position to close".bSmartLocalized).font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                        Picker("Position to close".bSmartLocalized, selection: $reductionPercent) {
                            ForEach([25, 50, 75, 100], id: \.self) { Text("\($0)%").tag($0) }
                        }.pickerStyle(.segmented).accessibilityIdentifier("trade.live.reduction")
                    }.disabled(store.isBusy)
                } else {
                    LiveOrderAmountPanel(amount: $amount, summary: summary, accent: accent, market: market,
                                         isLocked: store.preview != nil || store.result != nil)
                        .disabled(store.isBusy)
                }
                if let quote = store.preview {
                    HStack {
                        Text("Review order".bSmartLocalized).font(.headline)
                        Spacer()
                        Button { store.invalidate() } label: {
                            Image(systemName: "pencil").frame(width: 44, height: 44)
                        }.accessibilityLabel("Edit".bSmartLocalized).accessibilityIdentifier("trade.live.edit")
                    }
                    VStack(spacing: 12) {
                        if quote.order.reduceOnly {
                            metric("Position action", (quote.order.side == .buy ? "Close short" : "Close long").bSmartLocalized)
                        }
                        metric("Quantity", quote.order.size.wire)
                        if !quote.quote.fullyCovered {
                            metric("Estimated fill quantity", quantity(quote.quote.quotedSize, quote: quote))
                            metric("May remain open", quantity(quote.quote.uncoveredSize, quote: quote))
                        }
                        metric("Estimated fill price", money(quote.quote.averagePrice))
                        metric("Limit price", quote.order.limitPrice.wire + " USDC")
                        metric("Leverage", "\(quote.reviewedLeverage)x · \(quote.reviewedMarginMode.rawValue)")
                        metric("Estimated fee", money(quote.quote.estimatedTotalFee))
                    }.font(.subheadline)
                    Text((reducing ? "Reduce-only orders cannot increase or reverse a position. Unfilled quantity stays open."
                          : "Market orders may fill partially. Leverage increases losses and liquidation risk.").bSmartLocalized)
                        .font(.footnote).foregroundStyle(BSmartColor.secondaryText)
                }
                if let result = store.result { LiveOrderRecordRow(record: result, fills: store.fills[result.id]) }
                if let error = store.errorMessage {
                    Text(error).font(.subheadline).foregroundStyle(BSmartColor.bear)
                        .accessibilityIdentifier("trade.live.error")
                }
                if store.preview == nil, let error = store.entryError {
                    Text(error).font(.caption).foregroundStyle(BSmartColor.secondaryText)
                }
            }.padding(.bottom, 8)
            }.scrollIndicators(.hidden)
            availableBalance
            confirmation
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .tint(BSmartColor.brand)
        .scrollDismissesKeyboard(.interactively)
        .task { if store.preview == nil { await store.loadEntry(wallet: wallet, dex: dex, coin: coin) } }
        .onChange(of: amount.text) { _, _ in store.invalidate() }
        .onChange(of: side) { _, _ in store.invalidate() }
        .onChange(of: slippage) { _, _ in store.invalidate() }
        .onChange(of: reducing) { _, _ in store.invalidate() }
        .onChange(of: reductionPercent) { _, _ in store.invalidate() }
        .onChange(of: enabled) { _, value in if !value { clear() } }
        .onChange(of: scenePhase) { _, value in
            if value == .background { clear() }
            else if value == .active, store.entryAccount == nil {
                Task { await store.loadEntry(wallet: wallet, dex: dex, coin: coin) }
            }
        }
        .onDisappear { clear() }
        .overlay { if scenePhase != .active { BSmartColor.ink.ignoresSafeArea() } }
    }

    private var accent: Color { reducing ? BSmartColor.brand : side == .buy ? BSmartColor.bull : BSmartColor.bear }
    private var notional: String { amount.text.hasSuffix(".") ? String(amount.text.dropLast()) : amount.text }
    private var summary: LiveOrderEntrySummary? {
        if let quote = store.preview { return .init(account: quote.account, feeRate: quote.quote.takerRate, side: quote.order.side) }
        guard let account = store.entryAccount, let fee = store.entryFeeRate else { return nil }
        return .init(account: account, feeRate: fee, side: side)
    }

    private var orderControls: some View {
        HStack(spacing: 12) {
            if !reducing {
                Picker("Side".bSmartLocalized, selection: $side) {
                    Text("Long".bSmartLocalized).tag(HyperliquidOrderIntent.Side.buy)
                    Text("Short".bSmartLocalized).tag(HyperliquidOrderIntent.Side.sell)
                }.pickerStyle(.segmented).frame(maxWidth: 200).accessibilityIdentifier("trade.live.side")
            }
            Spacer(minLength: 0)
            Menu {
                Picker("Position action".bSmartLocalized, selection: $reducing) {
                    Text("Open / Add".bSmartLocalized).tag(false)
                    Text("Reduce / Close".bSmartLocalized).tag(true)
                }
                Picker("Slippage limit".bSmartLocalized, selection: $slippage) {
                    Text("0.1%").tag(UInt64(10)); Text("0.5%").tag(UInt64(50)); Text("1%").tag(UInt64(100))
                }
            } label: {
                HStack(spacing: 6) {
                    if reducing { Text("Reduce / Close".bSmartLocalized).font(.subheadline) }
                    Image(systemName: "slider.horizontal.3").font(.system(size: 17))
                }.frame(minWidth: 44, minHeight: 44)
            }.accessibilityLabel("Position action".bSmartLocalized).accessibilityIdentifier("trade.live.action")
        }.disabled(store.isBusy || store.result != nil)
    }

    private var availableBalance: some View {
        HStack(spacing: 8) {
            Text("%@ available".bSmartLocalized(summary.map { "$" + $0.capacity.availableToTrade.wire } ?? "--"))
                .font(.caption).foregroundStyle(BSmartColor.secondaryText).lineLimit(1).minimumScaleFactor(0.7)
                .accessibilityIdentifier("trading-account.summary")
            Spacer(minLength: 0)
            if store.preview == nil, store.result == nil, !reducing {
                Button {
                    if let maximum = summary?.maximumNotional(slippageBPS: slippage) { amount.setExact(maximum) }
                } label: { Text("MAX".bSmartLocalized).font(.caption.weight(.bold)).frame(minWidth: 44, minHeight: 36) }
                    .disabled(summary == nil || store.isBusy).accessibilityIdentifier("trade.amount.max")
            }
            Button { Task { await store.loadEntry(wallet: wallet, dex: dex, coin: coin) } } label: {
                if store.isLoadingEntry { ProgressView().frame(width: 36, height: 36) }
                else { Image(systemName: "arrow.clockwise").frame(width: 36, height: 36) }
            }.disabled(store.isBusy || store.isLoadingEntry || store.preview != nil)
                .accessibilityLabel("Refresh".bSmartLocalized).accessibilityIdentifier("trade.live.refresh-balance")
        }.foregroundStyle(accent)
    }

    @ViewBuilder private var confirmation: some View {
        if store.result != nil {
            Button("Done".bSmartLocalized) { dismiss() }
                .font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(BSmartColor.onAccent).background(accent, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityIdentifier("trade.live.done")
        } else if store.preview != nil {
            TradeSlideToConfirm(title: "Slide to %@".bSmartLocalized(
                (reducing ? "Confirm reduction" : side == .buy ? "Long" : "Short").bSmartLocalized),
                accent: accent, isEnabled: enabled && !store.isBusy && scenePhase == .active,
                action: { advance() }, identifier: "trade.live.confirm")
        } else {
            Button(action: advance) {
                HStack(spacing: 8) {
                    if store.isBusy { ProgressView() }
                    else { Image(systemName: "arrow.right") }
                    Text("Review order".bSmartLocalized)
                }.font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(BSmartColor.onAccent).background(accent, in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain).disabled(!enabled || store.isBusy || scenePhase != .active || (!reducing && amount.value <= 0))
                .accessibilityIdentifier("trade.live.confirm")
        }
    }

    private func advance() {
        guard enabled, !store.isBusy, scenePhase == .active else { return }
        operation = Task {
            if store.preview != nil { await store.confirm(wallet: wallet) }
            else if reducing {
                await store.reviewReduction(percent: reductionPercent, slippageBPS: slippage, wallet: wallet, dex: dex, coin: coin)
            } else { await store.review(notional: notional, side: side, slippageBPS: slippage, wallet: wallet, dex: dex, coin: coin) }
        }
    }

    private func clear() { operation?.cancel(); operation = nil; store.invalidate(); store.clearEntry() }
    private func money(_ value: HyperliquidExactValue) -> String {
        ((try? value.rounded(decimalPlaces: 6, up: true).wire) ?? "--") + " USDC"
    }
    private func quantity(_ value: HyperliquidExactValue, quote: HyperliquidOrderPreview) -> String {
        (try? value.rounded(decimalPlaces: quote.order.market.sizeDecimals, up: false).wire) ?? "--"
    }
    private func metric(_ title: String, _ value: String) -> some View {
        HStack { Text(title.bSmartLocalized).foregroundStyle(BSmartColor.secondaryText); Spacer(); Text(value).monospacedDigit() }
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
