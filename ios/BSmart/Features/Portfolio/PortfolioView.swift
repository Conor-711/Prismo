import SwiftUI

enum PortfolioSection: String, CaseIterable, Identifiable {
    case watchlist, holdings, allTickers
    var id: Self { self }
    var title: String {
        switch self { case .watchlist: "Favorites"; case .holdings: "Holdings"; case .allTickers: "All tickers" }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var accountScope: PortfolioAccountScope = .external
    @State private var isAddingEntry = false
    @State private var isShowingSettings = false
    @State private var isShowingBrokerageConnections = false
    @State private var section: PortfolioSection = .holdings
    @State private var isSearchingCatalog = false
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
                    case .allTickers:
                        AllTickersView(isActive: section == .allTickers) { isSearchingCatalog = $0 }
                    }
                },
                refresh: { await trading.loadFullCatalog() }
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("portfolio.list-pager")
            .background(BSmartColor.ink)
            .navigationTitle(language.localized("My profile"))
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("portfolio.screen")
            .overlay(alignment: .bottomTrailing) {
                ProfileAssistantLauncher()
                    .padding(.trailing, 22)
                    .padding(.bottom, 88)
            }
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 18) {
                accountSelector(.external, value: portfolioValueLabel)
                accountSelector(.inApp, value: "USDC")
            }
            if accountScope == .external { PortfolioValueChart(history: model.portfolioHistory) }
            if accountScope == .inApp {
                PortfolioAppAccountView()
            } else if !model.heldPositions.isEmpty && !model.hasCompletePortfolioValuation {
                Text("Partial valuation".bSmartLocalized).font(.caption).foregroundStyle(BSmartColor.secondaryText)
            }
        }
        .padding(.top, 8).padding(.bottom, 6)
    }

    private func accountSelector(_ scope: PortfolioAccountScope, value: String) -> some View {
        Button { accountScope = scope } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 5) {
                    Text(scope.rawValue.bSmartLocalized).lineLimit(1).minimumScaleFactor(0.8)
                    if accountScope == scope { Circle().fill(BSmartColor.brand).frame(width: 5, height: 5) }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(accountScope == scope ? BSmartColor.primaryText : BSmartColor.secondaryText)
                Text(value).font(.system(size: 23, weight: .semibold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.65).foregroundStyle(BSmartColor.primaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(accountScope == scope ? .isSelected : [])
        .accessibilityIdentifier("portfolio.account.\(scope == .external ? "external" : "app")")
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
        NavigationLink { TradingWalletView() } label: {
            HStack {
                Label("Trading wallet".bSmartLocalized, systemImage: "wallet.bifold")
                Spacer()
                Image(systemName: "chevron.right")
            }
            .font(.subheadline.weight(.semibold)).frame(minHeight: 48)
            .foregroundStyle(BSmartColor.primaryText)
        }.accessibilityIdentifier("portfolio.app.wallet")
    }

    private func entriesPanel(entries: [PortfolioPosition], emptyTitle: String, symbol: String) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if entries.isEmpty { emptyState(emptyTitle, symbol: symbol) }
            ForEach(entries) { entry in
                BSmartDetailNavigationLink(id: "portfolio-entry-\(entry.id)") {
                    TickerDestinationView(symbol: entry.ticker)
                } label: {
                    if entry.isPosition {
                        PortfolioHoldingRow(holding: .init(external: entry))
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
