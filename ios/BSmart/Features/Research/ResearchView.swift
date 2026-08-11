import SwiftUI

struct ResearchView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var language: AppLanguageStore
    @State private var query = ""

    private var filteredIntelligence: [TickerIntelligence] {
        guard !query.isEmpty else { return model.intelligence }
        return model.intelligence.filter {
            $0.ticker.localizedCaseInsensitiveContains(query)
                || $0.companyName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
                    searchField

                    BSmartSectionTitle(
                        title: "Current intelligence",
                        detail: "%d supported stocks".bSmartLocalized(filteredIntelligence.count)
                    )

                    if filteredIntelligence.isEmpty {
                        ContentUnavailableView.search(text: query)
                            .frame(maxWidth: .infinity)
                            .padding(.top, BSmartSpacing.xxxLarge)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filteredIntelligence.enumerated()), id: \.element.id) { index, ticker in
                                NavigationLink(value: ticker) {
                                    researchRow(ticker)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("research.ticker.\(ticker.ticker)")

                                if index < filteredIntelligence.count - 1 {
                                    Divider()
                                        .overlay(BSmartColor.line)
                                }
                            }
                        }
                        .background(BSmartColor.surface)
                        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                                .stroke(BSmartColor.line, lineWidth: 0.6)
                        }
                    }
                }
                .padding(.horizontal, BSmartSpacing.large)
                .padding(.vertical, BSmartSpacing.medium)
            }
            .background(BSmartColor.ink)
            .navigationTitle(language.localized("Intelligence"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: TickerIntelligence.self) { ticker in
                TickerIntelligenceView(ticker: ticker)
            }
            .navigationDestination(for: PortfolioSignal.self) { signal in
                EventDetailView(signal: signal)
            }
            .accessibilityIdentifier("research.screen")
        }
        .bSmartPage()
    }

    private var searchField: some View {
        HStack(spacing: BSmartSpacing.small) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(BSmartColor.tertiaryText)

            TextField("Ticker or company", text: $query)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(BSmartColor.tertiaryText)
                }
                .accessibilityLabel("Clear")
            }
        }
        .font(.subheadline)
        .padding(.horizontal, BSmartSpacing.medium)
        .frame(height: 44)
        .background(BSmartColor.recessed)
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous)
                .stroke(BSmartColor.line, lineWidth: 0.6)
        }
    }

    private func researchRow(_ ticker: TickerIntelligence) -> some View {
        HStack(alignment: .top, spacing: BSmartSpacing.medium) {
            BSmartAssetMark(ticker: ticker.ticker, size: 40)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(ticker.ticker)
                        .font(.subheadline.weight(.black))
                    Text(ticker.companyName)
                        .font(.caption)
                        .foregroundStyle(BSmartColor.tertiaryText)
                        .lineLimit(1)
                }

                Text(ticker.conclusion.bSmartLocalized)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(BSmartColor.primaryText)
                    .lineLimit(2)

                HStack(spacing: BSmartSpacing.small) {
                    Label("\(ticker.smartAccount.qualifiedAuthorCount)", systemImage: "person.wave.2")
                    Label("\(ticker.smartMoney.qualifiedAccountCount)", systemImage: "wallet.bifold")
                    Text("·")
                    Text(ticker.relationship.label.bSmartLocalized)
                        .foregroundStyle(ticker.direction.color)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(BSmartColor.tertiaryText)
            }

            Spacer(minLength: BSmartSpacing.xSmall)

            VStack(alignment: .trailing, spacing: 4) {
                Text(ticker.currentPrice.formatted(.currency(code: "USD").precision(.fractionLength(2))))
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                Text(ticker.dayChangePercent.formatted(.percent.precision(.fractionLength(1)).sign(strategy: .always())))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(ticker.dayChangePercent >= 0 ? BSmartColor.brand : BSmartColor.bear)
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(BSmartColor.tertiaryText)
                    .padding(.top, 4)
            }
        }
        .padding(BSmartSpacing.medium)
        .contentShape(Rectangle())
    }
}
