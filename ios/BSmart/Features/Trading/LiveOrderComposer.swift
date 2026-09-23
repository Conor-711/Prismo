import SwiftUI

struct LiveOrderComposer: View {
    let wallet: DeviceWalletSummary
    let coin: String
    let dex: String
    let side: HyperliquidOrderIntent.Side
    let initialNotional: String
    let market: HyperliquidPerpMarket?
    let enabled: Bool
    @ObservedObject var store: HyperliquidMarketOrderStore
    @ObservedObject var balances: HyperCoreBalanceStore
    var reducing = false
    var hasOpinionSource = false
    @EnvironmentObject private var trading: HyperliquidTradingStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var amount = TradeAmountInput(fractionDigits: 6)
    @State private var leverage = 5
    @State private var initialized = false
    @State private var resolvedMarket: HyperliquidPerpMarket?
    @State private var operation: Task<Void, Never>?
    @State private var orderStartedAt: Date?
    @State private var isShowingDeposit = false

    @State private var selectedReduction: Bool?
    private var isReducing: Bool { selectedReduction ?? reducing }

    private var accent: Color { isReducing ? BSmartColor.brand : side == .buy ? BSmartColor.bull : BSmartColor.bear }
    private var busy: Bool { operation != nil || store.isBusy || store.isComposing }
    private var needsSharedBalance: Bool { !isReducing && summary?.needsSharedBalance == true }
    private var shouldOfferDeposit: Bool {
        !isReducing && summary?.shouldOfferDeposit(balance: balances.snapshot) == true
    }
    private var isCheckingDepositBalance: Bool {
        !isReducing && summary?.capacity.availableToTrade.isPositive == false && balances.isLoading
    }
    private var inputIssue: String? {
        guard !isReducing, !needsSharedBalance else { return nil }
        return summary?.openingIssue(margin: amount.text.hasSuffix(".") ? String(amount.text.dropLast()) : amount.text)
    }
    private var symbol: String { market?.symbol ?? coin.components(separatedBy: ":").last ?? coin }
    private var summary: LiveOrderEntrySummary? {
        guard let account = store.entryAccount, let fee = store.entryFeeRate else { return nil }
        return .init(account: account, feeRate: fee, side: side, selectedLeverage: leverage)
    }
    private var validAmount: Bool {
        if isReducing {
            guard let percent = Int(amount.text), let size = summary?.reductionQuantity(percent: percent),
                  let quantity = try? HyperliquidOrderDecimal(size) else { return false }
            return quantity.isPositive
        }
        return amount.value > 0 && summary != nil && !needsSharedBalance && inputIssue == nil
    }
    private var available: String {
        if isReducing { return summary?.account.position.map { $0.quantity.magnitude.wire + " " + symbol } ?? "--" }
        return summary.map { "$" + $0.balance } ?? "--"
    }
    private var submitTitle: String {
        if needsSharedBalance { return "Preparing trading balance".bSmartLocalized }
        if let inputIssue { return inputIssue }
        if isReducing, summary?.account.position == nil { return "No open positions".bSmartLocalized }
        guard validAmount else { return "Enter an amount".bSmartLocalized }
        if isReducing { return "Slide to close %@".bSmartLocalized(symbol) }
        return "Slide to %@ %@".bSmartLocalized((side == .buy ? "Long" : "Short").bSmartLocalized, symbol)
    }

    var body: some View {
        VStack(spacing: 10) {
            if let result = store.result {
                completion(result).frame(maxHeight: .infinity)
            } else {
                if store.entryAccount?.position != nil || isReducing {
                    Picker("Order action".bSmartLocalized, selection: Binding(
                        get: { isReducing }, set: selectReduction)) {
                        Text((side == .buy ? "Long" : "Short").bSmartLocalized).tag(false)
                        Text("Close position".bSmartLocalized).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .disabled(busy || store.isLoadingEntry)
                    .accessibilityIdentifier("trade.position.action")
                }
                ScrollView {
                    LiveOrderAmountPanel(amount: $amount, leverage: $leverage, summary: summary, accent: accent,
                        market: market ?? resolvedMarket, isLocked: false, reducing: isReducing)
                        .disabled(busy || shouldOfferDeposit).padding(.bottom, 8)
                }.scrollIndicators(.hidden)
                if needsSharedBalance && !shouldOfferDeposit {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("USDC is not shared with this market.".bSmartLocalized)
                            .font(.caption).foregroundStyle(BSmartColor.secondaryText)
                        UnifiedAccountSetupView(wallet: wallet, compact: true, onEnabled: refreshEntry)
                    }.accessibilityIdentifier("trade.balance.setup")
                }
                HStack {
                    Text("%@ available".bSmartLocalized(available))
                        .font(.caption).foregroundStyle(BSmartColor.secondaryText)
                        .accessibilityIdentifier("trading-account.summary")
                    Spacer()
                    Button(action: refreshEntry) {
                        Image(systemName: "arrow.clockwise").frame(width: 36, height: 36)
                    }.buttonStyle(.plain).foregroundStyle(accent)
                        .accessibilityLabel("Refresh".bSmartLocalized)
                        .accessibilityIdentifier("trade.balance.refresh")
                        .disabled(busy || store.isLoadingEntry)
                    Button("MAX".bSmartLocalized) {
                        if isReducing { amount.setExact("100") }
                        else if let maximum = summary?.maximumMargin() { amount.setExact(maximum) }
                    }.font(.caption.weight(.bold)).foregroundStyle(accent).frame(minWidth: 44, minHeight: 32)
                        .disabled(busy || summary == nil || shouldOfferDeposit)
                        .accessibilityIdentifier("trade.amount.max")
                }
                if let error = store.errorMessage ?? store.entryError {
                    Text(error).font(.caption).foregroundStyle(BSmartColor.bear)
                        .frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("trading-order.error")
                }
                if !isReducing, !shouldOfferDeposit, summary?.capacity.availableToTrade.isPositive == false,
                   let balanceError = balances.errorMessage {
                    Text(balanceError).font(.caption).foregroundStyle(BSmartColor.bear)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if busy {
                    TimelineView(.periodic(from: orderStartedAt ?? .now, by: 1)) { context in
                        HStack(spacing: 12) {
                            ProgressView().tint(accent)
                            Text(store.phase.rawValue.bSmartLocalized).font(.subheadline.weight(.semibold))
                            Spacer(minLength: 8)
                            if let orderStartedAt {
                                Text("\(max(0, Int(context.date.timeIntervalSince(orderStartedAt))))s")
                                    .font(.caption.monospacedDigit()).foregroundStyle(BSmartColor.secondaryText)
                            }
                        }.padding(.horizontal, 18).frame(maxWidth: .infinity).frame(height: 60)
                            .foregroundStyle(accent)
                            .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    }.accessibilityIdentifier("trade.order.progress")
                } else if store.isLoadingEntry || isCheckingDepositBalance {
                    ProgressView()
                        .tint(BSmartColor.electric)
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .accessibilityIdentifier("trade.balance.checking")
                } else if shouldOfferDeposit {
                    Button { isShowingDeposit = true } label: {
                        Text("Deposit".bSmartLocalized)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity, minHeight: 60)
                            .background(BSmartColor.electric, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(!enabled || scenePhase != .active)
                    .accessibilityIdentifier("trade.deposit")
                } else {
                    TradeSlideToConfirm(title: submitTitle,
                        accent: accent, isEnabled: enabled && validAmount && scenePhase == .active,
                        action: placeOrder)
                }
            }
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier(store.result == nil ? "trade.composer" : "trade.order.filled")
        .task {
            async let entry: Void = store.loadEntry(wallet: wallet, dex: dex, coin: coin)
            async let balance: Void = balances.refresh(wallet: wallet)
            _ = await (entry, balance)
            initializeAmount()
        }
        .task(id: coin) {
            if market == nil { resolvedMarket = try? await trading.freshMarket(coin: coin, symbol: symbol) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { clear() }
            else if phase == .active {
                Task {
                    if store.entryAccount == nil {
                        await store.loadEntry(wallet: wallet, dex: dex, coin: coin)
                        initializeAmount()
                    }
                    await balances.refresh(wallet: wallet)
                }
            }
        }
        .onChange(of: enabled) { _, value in if !value { clear() } }
        .onChange(of: store.result?.id) { _, _ in
            if let result = store.result, case .filled = result.acknowledgement {
                NotificationCenter.default.post(name: .bSmartTradeFilled, object: nil)
            }
        }
        .onDisappear { clear() }
        .overlay { if scenePhase != .active { BSmartColor.ink.ignoresSafeArea() } }
        .sheet(isPresented: $isShowingDeposit, onDismiss: refreshEntry) {
            NavigationStack {
                PortfolioAppAccountView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done".bSmartLocalized) { isShowingDeposit = false }
                        }
                    }
            }
            .presentationDetents([.large])
        }
    }

    private func selectReduction(_ value: Bool) {
        guard !busy, !store.isLoadingEntry, value != isReducing,
              !value || store.entryAccount?.position != nil else { return }
        store.invalidate()
        selectedReduction = value
        amount = TradeAmountInput(text: value ? "100" : "0", fractionDigits: value ? 0 : 6)
        if let account = store.entryAccount { leverage = account.active.leverage.multiplier }
    }

    private func initializeAmount() {
        guard !initialized, let account = store.entryAccount else { return }
        leverage = account.active.leverage.multiplier
        if isReducing { amount = TradeAmountInput(text: "100", fractionDigits: 0) }
        else if let notional = try? HyperliquidOrderDecimal(initialNotional),
           let margin = try? HyperliquidExactValue(notional).divided(by: .init(UInt64(leverage))).rounded(decimalPlaces: 6, up: false) {
            amount.setExact(margin.wire)
        }
        initialized = true
    }

    private func refreshEntry() {
        guard !busy else { return }
        Task {
            async let entry: Void = store.loadEntry(wallet: wallet, dex: dex, coin: coin)
            async let balance: Void = balances.refresh(wallet: wallet)
            _ = await (entry, balance)
            initializeAmount()
        }
    }

    private func placeOrder() {
        guard enabled, !busy, scenePhase == .active, validAmount else { return }
        let value = amount.text.hasSuffix(".") ? String(amount.text.dropLast()) : amount.text
        let multiple = leverage
        orderStartedAt = .now
        operation = Task {
            if isReducing, let percent = Int(value) {
                await store.executeReduction(percent: percent, wallet: wallet, dex: dex, coin: coin)
            } else if !isReducing {
                await store.executeMargin(value, leverage: multiple, side: side, wallet: wallet, dex: dex, coin: coin)
            }
            operation = nil
        }
    }

    private func clear() {
        operation?.cancel(); operation = nil; store.invalidate(); store.clearEntry(); balances.clear()
    }

    private func completion(_ record: HyperliquidOrderRecord) -> some View {
        VStack(spacing: 24) {
            Image(systemName: completionSymbol(record))
                .font(.system(size: 56)).foregroundStyle(accent)
            LiveOrderRecordRow(record: record, fills: store.fills[record.id])
            if hasOpinionSource, !record.order.reduceOnly, case .filled = record.acknowledgement {
                TradeThesisAfterFill(record: record, accent: accent)
            }
            Button("Done".bSmartLocalized) { dismiss() }
                .font(.headline).foregroundStyle(BSmartColor.onAccent).frame(maxWidth: .infinity, minHeight: 52)
                .background(accent, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityIdentifier("trade.order.done")
        }.padding(.vertical, 48)
    }

    private func completionSymbol(_ record: HyperliquidOrderRecord) -> String {
        switch record.acknowledgement {
        case .filled: "checkmark.circle.fill"
        case .rejected: "xmark.circle"
        default: "clock.badge.exclamationmark"
        }
    }

}
