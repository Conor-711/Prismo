import SwiftUI

struct AllTickersView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""

    private var filteredIntelligence: [TickerIntelligence] {
        let source = model.intelligence.sorted { lhs, rhs in
            if lhs.ticker != rhs.ticker { return lhs.ticker < rhs.ticker }
            return lhs.companyName < rhs.companyName
        }
        guard !query.isEmpty else { return source }
        return source.filter {
            $0.ticker.localizedCaseInsensitiveContains(query)
                || $0.companyName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
                searchField

                BSmartSectionTitle(
                    title: query.isEmpty ? "All supported tickers" : "Search results",
                    detail: "%d of %d supported tickers".bSmartLocalized(
                        filteredIntelligence.count,
                        model.intelligence.count
                    )
                )

                if filteredIntelligence.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .frame(maxWidth: .infinity)
                        .padding(.top, BSmartSpacing.xxxLarge)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredIntelligence.enumerated()), id: \.element.id) { index, ticker in
                            BSmartDetailNavigationLink(id: "ticker-\(ticker.ticker)") {
                                TickerIntelligenceView(ticker: ticker)
                            } label: {
                                tickerRow(ticker)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("portfolio.ticker.\(ticker.ticker)")

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
        .accessibilityIdentifier("portfolio.all-tickers")
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

    private func tickerRow(_ ticker: TickerIntelligence) -> some View {
        let latestAccount = model.accountUpdates(for: ticker.ticker)
            .max { $0.publishedAt < $1.publishedAt }
        let latestMoney = model.moneyMovements(for: ticker.ticker)
            .max { $0.observedAt < $1.observedAt }

        return HStack(alignment: .top, spacing: BSmartSpacing.medium) {
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

                Text(tickerSummary(ticker, account: latestAccount, money: latestMoney))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(BSmartColor.primaryText)
                    .lineLimit(2)

                HStack(spacing: BSmartSpacing.small) {
                    Label("\(ticker.smartAccount.qualifiedAuthorCount)", systemImage: "person.wave.2")
                    Label("\(ticker.smartMoney.qualifiedAccountCount)", systemImage: "wallet.bifold")
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

    private func tickerSummary(
        _ ticker: TickerIntelligence,
        account: SmartAccountUpdate?,
        money: SmartMoneyMovement?
    ) -> String {
        switch (account, money) {
        case let (account?, money?) where account.publishedAt >= money.observedAt:
            return accountTitle(account)
        case let (_, money?):
            return "%@ %@ %@".bSmartLocalized(
                money.publicIdentity.displayName,
                money.action.label,
                ticker.ticker
            )
        case let (account?, nil):
            return accountTitle(account)
        case (nil, nil):
            return "No recent Smart Account or Smart Money update".bSmartLocalized
        }
    }

    private func accountTitle(_ update: SmartAccountUpdate) -> String {
        let value = BSmartLocalization.isSimplifiedChinese
            ? (nonBlank(update.activityTitleZH) ?? nonBlank(update.activityTitle))
            : (nonBlank(update.activityTitleEN) ?? nonBlank(update.activityTitle))
        return value ?? update.thesis
    }

    private func nonBlank(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
