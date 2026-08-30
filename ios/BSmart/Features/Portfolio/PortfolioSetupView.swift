import SwiftUI

private struct PortfolioSetupDraft: Identifiable {
    let intelligence: TickerIntelligence
    let kind: PortfolioEntryKind

    var id: String { "\(intelligence.ticker)-\(kind.rawValue)" }
}

struct PortfolioSetupView: View {
    @EnvironmentObject private var model: AppModel
    @State private var draft: PortfolioSetupDraft?
    @State private var isShowingBrokerageConnections = false
    @State private var isAddingTicker = false
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: BSmartSpacing.xLarge) {
                    header
                    brokerageEntry

                    HStack {
                        BSmartSectionHeader(
                            title: "Stocks",
                            detail: "\(filteredIntelligence.count)"
                        )
                        Spacer()
                        Button("Add ticker".bSmartLocalized) { isAddingTicker = true }
                            .font(.caption.weight(.bold))
                    }

                    ForEach(filteredIntelligence) { item in
                        tickerRow(item)
                    }
                }
                .padding(BSmartSpacing.large)
                .padding(.bottom, 96)
            }
            .background(BSmartColor.ink)
            .searchable(text: $searchText, prompt: "Ticker or company".bSmartLocalized)
            .safeAreaInset(edge: .bottom) {
                continueBar
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $draft) { draft in
                AddPositionView(
                    prefilledTicker: draft.intelligence.ticker,
                    prefilledCompanyName: draft.intelligence.companyName,
                    initialKind: draft.kind
                )
                .environmentObject(model)
            }
            .sheet(isPresented: $isShowingBrokerageConnections) {
                BrokerageConnectionView()
                    .environmentObject(model)
            }
            .sheet(isPresented: $isAddingTicker) {
                AddPositionView()
                    .environmentObject(model)
            }
        }
        .accessibilityIdentifier("portfolio-setup.screen")
        .bSmartPage()
    }

    private var filteredIntelligence: [TickerIntelligence] {
        let available = model.intelligence + Self.additionalTickerOptions.filter { option in
            !model.intelligence.contains { $0.ticker.caseInsensitiveCompare(option.ticker) == .orderedSame }
        }.map { Self.placeholderIntelligence($0) }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return available }
        return available.filter {
            $0.ticker.localizedCaseInsensitiveContains(query)
                || $0.companyName.localizedCaseInsensitiveContains(query)
        }
    }

    private static let additionalTickerOptions: [(ticker: String, companyName: String)] = [
        ("AAPL", "Apple"), ("MSFT", "Microsoft"), ("AMZN", "Amazon"),
        ("GOOGL", "Alphabet"), ("META", "Meta Platforms"), ("TSM", "Taiwan Semiconductor"),
        ("AMD", "Advanced Micro Devices"), ("AVGO", "Broadcom"), ("MU", "Micron Technology"),
        ("NFLX", "Netflix"), ("TSLA", "Tesla"), ("QCOM", "Qualcomm"),
        ("MRVL", "Marvell Technology"), ("COHR", "Coherent"), ("CRCL", "Circle"),
        ("MSTR", "Strategy"), ("RKLB", "Rocket Lab"), ("NBIS", "Nebius")
    ]

    private static func placeholderIntelligence(_ option: (ticker: String, companyName: String)) -> TickerIntelligence {
        TickerIntelligence(
            ticker: option.ticker,
            companyName: option.companyName,
            currentPrice: 0,
            dayChangePercent: 0,
            dataAsOf: .now,
            relationship: .confirmation,
            direction: .neutral,
            conclusion: "",
            latestSignalId: nil,
            smartAccount: SmartAccountSnapshot(direction: .neutral, headline: "", detail: "", qualifiedAuthorCount: 0, latestUpdateAt: nil),
            smartMoney: SmartMoneySnapshot(coverage: .unavailable, direction: .neutral, headline: "", detail: "", qualifiedAccountCount: 0, latestMovementAt: nil)
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            BSmartWordmark(fontSize: 24)

            Text("Start with your stocks")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))

            if let updatedAt = model.lastDataRefreshAt {
                Label(
                    "Updated %@".bSmartLocalized(updatedAt.bSmartDataTimestamp),
                    systemImage: "clock.arrow.circlepath"
                )
                .font(.caption)
                .foregroundStyle(BSmartColor.tertiaryText)
                .monospacedDigit()
                .accessibilityIdentifier("portfolio-setup.data-updated-at")
            }
        }
        .padding(.top, BSmartSpacing.large)
    }

    private var valueStrip: some View {
        HStack(spacing: 0) {
            setupValue(
                symbol: "person.wave.2.fill",
                title: "Smart Account",
                detail: "Latest qualified views"
            )
            Divider()
                .overlay(BSmartColor.line)
                .padding(.vertical, BSmartSpacing.medium)
            setupValue(
                symbol: "wallet.bifold.fill",
                title: "Smart Money",
                detail: "Public capital moves"
            )
        }
        .frame(maxWidth: .infinity)
        .background(BSmartColor.elevated)
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                .stroke(BSmartColor.brand.opacity(0.24), lineWidth: 0.75)
        }
    }

    private var brokerageEntry: some View {
        Button {
            isShowingBrokerageConnections = true
        } label: {
            HStack(spacing: BSmartSpacing.medium) {
                Image(systemName: "link.badge.plus")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(BSmartColor.pulseInk)
                    .frame(width: 42, height: 42)
                    .background(BSmartColor.brand)
                    .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))

                Text("Link a brokerage".bSmartLocalized)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BSmartColor.primaryText)

                Spacer(minLength: BSmartSpacing.small)

                if model.linkedBrokerageAccounts.isEmpty {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BSmartColor.tertiaryText)
                } else {
                    Label("%d linked".bSmartLocalized(model.linkedBrokerageAccounts.count), systemImage: "checkmark.circle.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(BSmartColor.brand)
                }
            }
            .bSmartSurface(padding: BSmartSpacing.medium)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("portfolio-setup.link-brokerage")
    }

    private func setupValue(symbol: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.small) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(BSmartColor.brand)
            Text(title.bSmartLocalized)
                .font(.caption.weight(.bold))
            Text(detail.bSmartLocalized)
                .font(.caption2)
                .foregroundStyle(BSmartColor.secondaryText)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BSmartSpacing.large)
    }

    private func tickerRow(_ item: TickerIntelligence) -> some View {
        HStack(spacing: BSmartSpacing.medium) {
            BSmartAssetMark(ticker: item.ticker, size: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.ticker)
                    .font(.subheadline.weight(.bold))
                Text(item.companyName)
                    .font(.caption)
                    .foregroundStyle(BSmartColor.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: BSmartSpacing.small)

            if let entry = model.position(for: item.ticker) {
                Label(
                    (entry.isPosition ? "Position" : "Watching").bSmartLocalized,
                    systemImage: "checkmark.circle.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(BSmartColor.brand)
                .labelStyle(.titleAndIcon)
            } else {
                Button {
                    draft = PortfolioSetupDraft(intelligence: item, kind: .position)
                } label: {
                    Text("Hold".bSmartLocalized)
                        .font(.caption.weight(.bold))
                        .frame(minWidth: 48, minHeight: 34)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Add %@ position".bSmartLocalized(item.ticker))

                Button {
                    _ = model.savePortfolioEntry(
                        id: nil,
                        ticker: item.ticker,
                        companyName: item.companyName,
                        kind: .watchlist,
                        shares: nil,
                        averageCost: nil,
                        portfolioWeight: nil
                    )
                } label: {
                    Text("Watch".bSmartLocalized)
                        .font(.caption.weight(.bold))
                        .frame(minWidth: 48, minHeight: 34)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Watch %@".bSmartLocalized(item.ticker))
                .accessibilityIdentifier("portfolio-setup.watch.\(item.ticker)")
            }
        }
        .bSmartSurface(padding: BSmartSpacing.medium)
    }

    private var continueBar: some View {
        VStack(spacing: BSmartSpacing.small) {
            Button {
                _ = model.completePortfolioSetup()
            } label: {
                HStack {
                    Text((model.positions.isEmpty ? "Choose at least one stock" : "Open my signal feed").bSmartLocalized)
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.headline)
                .foregroundStyle(BSmartColor.ink)
                .padding(.horizontal, BSmartSpacing.large)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(BSmartColor.brand)
                .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))
            }
            .disabled(model.positions.isEmpty)
            .opacity(model.positions.isEmpty ? 0.45 : 1)
            .accessibilityIdentifier("portfolio-setup.continue")

            if !model.positions.isEmpty {
                Text((model.positions.count == 1 ? "%d ticker selected" : "%d tickers selected")
                    .bSmartLocalized(model.positions.count))
                    .font(.caption2)
                    .foregroundStyle(BSmartColor.secondaryText)
            }
        }
        .padding(.horizontal, BSmartSpacing.large)
        .padding(.top, BSmartSpacing.medium)
        .padding(.bottom, BSmartSpacing.small)
        .background(.ultraThinMaterial)
    }
}
