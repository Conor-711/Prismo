import SwiftUI

private struct PortfolioSetupDraft: Identifiable {
    let intelligence: TickerIntelligence
    let kind: PortfolioEntryKind

    var id: String { "\(intelligence.ticker)-\(kind.rawValue)" }
}

struct PortfolioSetupView: View {
    @EnvironmentObject private var model: AppModel
    @State private var draft: PortfolioSetupDraft?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: BSmartSpacing.xLarge) {
                    header
                    valueStrip

                    BSmartSectionHeader(
                        title: "Covered now",
                        detail: "\(model.intelligence.count) launch tickers"
                    )

                    ForEach(model.intelligence) { item in
                        tickerRow(item)
                    }
                }
                .padding(BSmartSpacing.large)
                .padding(.bottom, 96)
            }
            .background(BSmartColor.ink)
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
        }
        .accessibilityIdentifier("portfolio-setup.screen")
        .bSmartPage()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            BSmartWordmark(fontSize: 24)

            Text("Start with your stocks")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))

            Text("Add a position for portfolio-aware impact, or watch a stock before you buy.")
                .font(.body)
                .foregroundStyle(BSmartColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

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
                    Image(systemName: "briefcase.fill")
                        .frame(width: 38, height: 38)
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
                    Image(systemName: "eye.fill")
                        .frame(width: 38, height: 38)
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
