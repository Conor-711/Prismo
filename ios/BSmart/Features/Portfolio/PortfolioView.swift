import SwiftUI

enum PortfolioSection: String, CaseIterable, Identifiable {
    case watchlist, holdings, allTickers, activity
    var id: Self { self }
    var title: String {
        switch self { case .watchlist: "Favorites"; case .holdings: "Holdings"; case .allTickers: "All tickers"; case .activity: "Trade history" }
    }
}

private enum PortfolioAccountScope: String {
    case external = "External holdings"
    case inApp = "bSmart account"
}

struct PortfolioView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var language: AppLanguageStore
    @EnvironmentObject private var trading: HyperliquidTradingStore
    @EnvironmentObject private var account: AccountAccessStore
    @EnvironmentObject private var wallet: DeviceWalletStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var accountScope: PortfolioAccountScope = .inApp
    @State private var isAddingEntry = false
    @State private var isShowingSettings = false
    @State private var isShowingBrokerageConnections = false
    @State private var isShowingWithdrawal = false
    @State private var section: PortfolioSection = .holdings
    @State private var isSearchingCatalog = false
    @State private var activityRefresh = 0
    @Namespace private var tabSelection

    var body: some View {
        NavigationStack {
            BSmartCollapsingPager(
                selection: $section, sections: PortfolioSection.allCases,
                collapseHeader: isSearchingCatalog && section == .allTickers,
                pageIdentifier: { "portfolio.page.\($0.rawValue)" },
                header: { _ in
                    VStack(alignment: .leading, spacing: 20) {
                        UserProfileHeader()
                        portfolioSummary
                    }
                        .padding(.horizontal, BSmartSpacing.large)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("portfolio.value-overview")
                },
                tabs: { sectionPicker },
                content: { item in
                    switch item {
                    case .watchlist: watchlistContent
                    case .holdings: holdingsContent
                    case .activity: ProfileTradeActivity(refresh: activityRefresh, isActive: section == .activity)
                    case .allTickers:
                        AllTickersView(isActive: section == .allTickers) { isSearchingCatalog = $0 }
                    }
                },
                refresh: {
                    if section == .activity { activityRefresh += 1 }
                    else { await trading.loadFullCatalog() }
                }
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("portfolio.list-pager")
            .background(BSmartColor.ink)
            .navigationTitle(language.localized("My profile"))
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("portfolio.screen")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { isShowingBrokerageConnections = true } label: { Image(systemName: "link") }
                        .accessibilityLabel("Brokerage connections".bSmartLocalized)
                        .accessibilityIdentifier("portfolio.brokerage-connections")
                    Button { isShowingSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Open settings".bSmartLocalized)
                        .accessibilityIdentifier("portfolio.settings")
                    Button { isAddingEntry = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add ticker".bSmartLocalized)
                }
            }
            .sheet(isPresented: $isAddingEntry) { AddPositionView().environmentObject(model) }
            .sheet(isPresented: $isShowingSettings) { AppSettingsView() }
            .sheet(isPresented: $isShowingBrokerageConnections) { BrokerageConnectionView().environmentObject(model) }
        }
        .bSmartPage()
        .sheet(isPresented: $isShowingWithdrawal) { AcrossWithdrawalSheet() }
        .task { if trading.marketCatalog.isEmpty { await trading.loadFullCatalog() } }
    }

    private var sectionPicker: some View {
        HStack(spacing: 24) {
            ForEach(PortfolioSection.allCases) { item in
                Button {
                    withAnimation(reduceMotion ? nil : BSmartMotion.quick) { section = item }
                } label: {
                    Text(item.title.bSmartLocalized)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(section == item ? BSmartColor.primaryText : BSmartColor.tertiaryText)
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .frame(minWidth: 44, minHeight: 48, alignment: .leading)
                        .contentShape(Rectangle())
                        .overlay(alignment: .bottomLeading) {
                            if section == item {
                                Capsule().fill(BSmartColor.pulse).frame(width: 40, height: 3)
                                    .matchedGeometryEffect(id: "portfolio.selection", in: tabSelection)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(section == item ? .isSelected : [])
                .accessibilityIdentifier("portfolio.tab.\(item.rawValue)")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, BSmartSpacing.large)
        .overlay(alignment: .bottom) { Rectangle().fill(BSmartColor.line).frame(height: 0.5) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("portfolio.section-picker")
    }

    private var portfolioSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            if accountScope == .inApp {
                if case .verified(let local) = wallet.state, local.accountID == account.identity?.id {
                    HyperCoreBalanceView(wallet: local, service: account, compact: true,
                                         accountTitle: accountScope.rawValue,
                                         switchDestinationTitle: PortfolioAccountScope.external.rawValue,
                                         switchAccount: toggleAccountScope)
                        .id(local.accountID.uuidString + local.address)
                } else {
                    HStack(spacing: 8) {
                        balanceText("--").accessibilityIdentifier("portfolio.account.balance-value")
                        Spacer(minLength: 0)
                        accountSwitch
                    }
                }
            } else {
                HStack(spacing: 8) {
                    balanceText(portfolioValueLabel).accessibilityIdentifier("portfolio.account.balance-value")
                    Spacer(minLength: 0)
                    accountSwitch
                }
                PortfolioValueChart(history: model.portfolioHistory)
                if !model.heldPositions.isEmpty && !model.hasCompletePortfolioValuation {
                    Text("Partial valuation".bSmartLocalized).font(.caption).foregroundStyle(BSmartColor.secondaryText)
                }
            }
        }
        .padding(.bottom, 6)
    }

    private func balanceText(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 38, weight: .semibold))
            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            .contentTransition(.numericText())
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.55), value: value)
    }

    private var accountSwitch: some View {
        PortfolioAccountSwitchButton(currentTitle: accountScope.rawValue,
                                     nextTitle: (accountScope == .inApp
                                                 ? PortfolioAccountScope.external : .inApp).rawValue,
                                     action: toggleAccountScope)
    }

    private func toggleAccountScope() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            accountScope = accountScope == .inApp ? .external : .inApp
        }
    }

    private var portfolioValueLabel: String {
        if model.heldPositions.isEmpty { return 0.0.formatted(.bSmartDollars) }
        guard model.hasAnyPortfolioValuation else { return "Not available".bSmartLocalized }
        return model.portfolioValue.formatted(.bSmartDollars.precision(.fractionLength(2)))
    }

    private var holdingsContent: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            if accountScope == .external {
                brokerageConnectionRow
                entriesPanel(entries: model.heldPositions, emptyTitle: "No positions yet", symbol: "chart.pie")
            } else {
                appHoldings
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("portfolio.holdings")
    }

    private var watchlistContent: some View {
        entriesPanel(entries: model.watchlist, emptyTitle: "No watched tickers", symbol: "star")
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("portfolio.watchlist")
    }

    private var appHoldings: some View {
        PortfolioTradingHoldingsView(isShowingWithdrawal: $isShowingWithdrawal)
    }

    private func entriesPanel(entries: [PortfolioPosition], emptyTitle: String, symbol: String) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if entries.isEmpty { emptyState(emptyTitle, symbol: symbol) }
            if entries.first?.isPosition == true { PortfolioCompactHoldingHeader().padding(.bottom, 8) }
            ForEach(entries) { entry in
                BSmartDetailNavigationLink(id: "portfolio-entry-\(entry.id)") {
                    TickerDestinationView(symbol: entry.ticker)
                } label: {
                    if entry.isPosition {
                        PortfolioCompactHoldingRow(holding: .init(external: entry), companyName: entry.companyName)
                    } else {
                        BSmartMarketRow(entry: model.tickerCatalog(markets: trading.marketCatalog).first { $0.symbol == entry.ticker }
                            ?? AppTickerCatalogEntry(symbol: entry.ticker, companyName: entry.companyName,
                                                     price: entry.currentPrice > 0 ? entry.currentPrice : nil))
                    }
                }
                .buttonStyle(.plain).accessibilityIdentifier("portfolio.entry.\(entry.ticker)")
                Divider().overlay(BSmartColor.line).padding(.leading, 58)
            }
        }
    }

    private func emptyState(_ title: String, symbol: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.title2).foregroundStyle(BSmartColor.tertiaryText)
            Text(title.bSmartLocalized).font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
            Button { isAddingEntry = true } label: { Label("Add ticker".bSmartLocalized, systemImage: "plus") }
                .font(.subheadline.weight(.semibold)).tint(BSmartColor.brand)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24)
    }

    private var brokerageConnectionRow: some View {
        Button { isShowingBrokerageConnections = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "link").foregroundStyle(BSmartColor.brand)
                Text((model.linkedBrokerageAccounts.isEmpty ? "Link a brokerage" : "Linked brokerages").bSmartLocalized)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                if !model.linkedBrokerageAccounts.isEmpty { Text("\(model.linkedBrokerageAccounts.count)").font(.caption) }
                Image(systemName: "chevron.right").font(.caption)
            }
            .foregroundStyle(BSmartColor.secondaryText).frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityIdentifier("portfolio.link-brokerage-row")
    }
}

struct PortfolioAccountSwitchButton: View {
    let currentTitle: String
    let nextTitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(displayTitle(currentTitle))
                    .lineLimit(1).minimumScaleFactor(0.8)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(BSmartColor.primaryText)
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .background(BSmartColor.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(BSmartColor.softDivider, lineWidth: 0.75))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Switch account".bSmartLocalized)
        .accessibilityValue(displayTitle(currentTitle))
        .accessibilityHint(displayTitle(nextTitle))
        .accessibilityIdentifier("portfolio.account.switch")
    }

    private func displayTitle(_ title: String) -> String {
        switch title {
        case "bSmart account": "Internal account".bSmartLocalized
        case "External holdings": "External account".bSmartLocalized
        default: title.bSmartLocalized
        }
    }
}
