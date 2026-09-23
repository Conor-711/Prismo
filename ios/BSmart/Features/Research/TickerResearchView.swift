import SwiftUI

private enum TickerIntelligenceSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case activity = "Smart Activity"
    case trade = "Trade"
    var id: Self { self }
}

struct TickerIntelligenceView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var trading: HyperliquidTradingStore
    let symbol: String
    @State private var showsPositionEditor = false
    @State private var showsMarketPicker = false
    @State private var selection: TickerIntelligenceSection = .overview

    init(symbol: String) { self.symbol = symbol.uppercased() }
    init(ticker: TickerIntelligence) { self.init(symbol: ticker.ticker) }

    private var activeSymbol: String { trading.activeMarket?.symbol ?? symbol }
    private var isCryptoMarket: Bool? {
        if let market = trading.activeMarket, market.symbol == activeSymbol {
            return market.dex.isEmpty
        }
        return trading.market(for: activeSymbol)?.dex.isEmpty
    }
    private var profile: TickerProfile? { TickerProfile.lookup(activeSymbol) }
    private var companyName: String {
        profile?.name ?? model.intelligence(for: activeSymbol)?.companyName
            ?? model.position(for: activeSymbol)?.companyName
            ?? model.accountUpdates(for: activeSymbol).first?.companyName ?? activeSymbol
    }
    private var activities: [TickerSmartActivityItem] {
        TickerSmartActivityItem.items(ticker: activeSymbol,
            accountUpdates: model.accountUpdates(for: activeSymbol),
            moneyMovements: model.moneyMovements(for: activeSymbol))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HyperliquidTradingView(symbol: symbol, activities: activities)
                TickerOwnHoldingsSection(symbol: activeSymbol)
                sectionPicker
                switch selection {
                case .overview:
                    TickerAboutSection(symbol: activeSymbol, companyName: companyName,
                                       profile: profile, market: trading.activeMarket,
                                       isCrypto: isCryptoMarket)
                case .activity:
                    TickerSmartActivityFeed(activities: activities, framed: false)
                        .id(activeSymbol)
                case .trade:
                    HyperliquidTradingDetails()
                }
            }
            .padding(16)
        }
        .background(BSmartColor.ink)
        .accessibilityIdentifier("ticker-intelligence.\(activeSymbol)")
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { assetNavigationHeader }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.setTickerFollowed(model.position(for: activeSymbol) == nil,
                                            ticker: activeSymbol, companyName: companyName)
                } label: {
                    Image(systemName: model.position(for: activeSymbol) == nil ? "star" : "star.fill")
                        .foregroundStyle(model.position(for: activeSymbol) == nil
                            ? BSmartColor.secondaryText : BSmartColor.brand)
                }
                .disabled(model.position(for: activeSymbol)?.isPosition == true)
                .accessibilityLabel((model.position(for: activeSymbol)?.isPosition == true
                    ? "In portfolio" : model.position(for: activeSymbol) == nil
                        ? "Follow ticker" : "Unfollow ticker").bSmartLocalized)
                .accessibilityIdentifier("ticker.follow")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsPositionEditor = true } label: {
                    Image(systemName: model.position(for: activeSymbol) == nil ? "plus.circle" : "pencil")
                }
                .accessibilityLabel((model.position(for: activeSymbol) == nil
                    ? "Add to portfolio or watchlist" : "Edit tracked ticker").bSmartLocalized)
                .accessibilityIdentifier(model.position(for: activeSymbol) == nil
                    ? "ticker-intelligence.track" : "ticker-intelligence.edit")
            }
        }
        .sheet(isPresented: $showsMarketPicker) {
            HyperliquidMarketPickerView().environmentObject(trading)
        }
        .sheet(isPresented: $showsPositionEditor) {
            AddPositionView(position: model.position(for: activeSymbol), prefilledTicker: activeSymbol,
                            prefilledCompanyName: companyName, initialKind: .watchlist)
                .environmentObject(model)
        }
        .bSmartDetailPage()
        .bSmartTradeDock(symbol: activeSymbol)
        .bSmartPage()
    }

    private var sectionPicker: some View {
        HStack(spacing: 0) {
            ForEach(TickerIntelligenceSection.allCases) { section in
                Button { selection = section } label: {
                    Text(section.rawValue.bSmartLocalized)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selection == section ? BSmartColor.primaryText : BSmartColor.tertiaryText)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(selection == section ? BSmartColor.brand : BSmartColor.line)
                                .frame(height: selection == section ? 2 : 0.5)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == section ? .isSelected : [])
                .accessibilityIdentifier("ticker.section.\(section.id)")
            }
        }
    }

    private var assetNavigationHeader: some View {
        Button { showsMarketPicker = true } label: {
            HStack(spacing: 9) {
                BSmartAssetMark(ticker: activeSymbol, size: 34, isCrypto: isCryptoMarket)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(activeSymbol).font(.system(size: 16, weight: .semibold))
                        if let market = trading.activeMarket {
                            Text("\(market.maxLeverage)x")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(BSmartColor.sky)
                        }
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                    }
                    Text(companyName).font(.caption2).foregroundStyle(BSmartColor.secondaryText)
                }
                .lineLimit(1)
            }
            .foregroundStyle(BSmartColor.primaryText)
            .frame(maxWidth: 230, minHeight: 44, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("trade.market-picker")
    }
}
