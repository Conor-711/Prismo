import SwiftUI

struct SmartAccountAboutSection: View {
    let account: SmartAccountProfile
    let updates: [SmartAccountUpdate]

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Investor profile".bSmartLocalized).font(.title3.weight(.bold))
                if let bio = account.description, !bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(bio).font(.subheadline).lineSpacing(4)
                        .foregroundStyle(BSmartColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(alignment: .top, spacing: 12) {
                    metric("Best field", account.specialty.bSmartLocalized)
                    metric("Best horizon", account.horizon.bSmartLocalized)
                    metric("Investment style", account.resolvedStyle.bSmartLocalized)
                }
                HStack(alignment: .top, spacing: 12) {
                    metric("Covered tickers", account.coveredTickers.map { $0.formatted() } ?? "--")
                    metric("Settled calls", account.settledCalls.map { $0.formatted() } ?? "--")
                    metric("Active days", account.activeDays.map { $0.formatted() } ?? "--")
                }
                if !account.resolvedTopTickers.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(account.resolvedTopTickers, id: \.self) { ticker in
                                HStack(spacing: 6) {
                                    BSmartAssetMark(ticker: ticker, size: 24)
                                    Text(ticker).font(.caption.weight(.semibold))
                                }
                                .frame(minHeight: 44).bSmartTickerDestination(ticker)
                            }
                        }
                    }
                }
            }
            .accessibilityIdentifier("smart.account.investor-profile")

            Divider().overlay(BSmartColor.line)
            VStack(alignment: .leading, spacing: 16) {
                Text("How is this account scored?".bSmartLocalized).font(.title3.weight(.bold))
                HStack(alignment: .top, spacing: 12) {
                    metric("Account Score", score(account.score))
                    metric("Platform rank", account.resolvedPlatformRank > 0 ? "#\(account.resolvedPlatformRank)" : "--")
                    metric("Platform percentile", percentile)
                }
                if account.marketSelectionScore != nil || account.industrySelectionScore != nil {
                    HStack(alignment: .top, spacing: 12) {
                        metric("vs S&P 500", score(account.marketSelectionScore))
                        metric("vs sector ETF", score(account.industrySelectionScore))
                    }
                }
                DisclosureGroup("Calculation and data limits".bSmartLocalized) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Scores evaluate historical public calls, not followers or verified account profits. Market and sector benchmarks measure two different stock-selection abilities.".bSmartLocalized)
                        Text("Under the integral methodology, directional excess returns accumulate across the call's evaluation window. Settled evidence is adjusted for sample strength and moderate time decay. The server's published scoring version remains authoritative.".bSmartLocalized)
                        HStack(alignment: .top, spacing: 12) {
                            metric("Evidence weight", account.effectiveSamples.map {
                                $0.formatted(.number.precision(.fractionLength(1)))
                            } ?? "--")
                            metric("Confidence", account.resolvedConfidence.capitalized.bSmartLocalized)
                        }
                        if let date = updates.compactMap(\.authorScoreAsOf).max() {
                            Text("Score snapshot %@".bSmartLocalized(date.bSmartCompactDate))
                        }
                        ForEach(Array(Set(updates.compactMap { $0.settlement?.settlementVersion })).sorted(), id: \.self) { version in
                            Text(version).font(.caption.monospaced())
                        }
                        Text("Featured works are selected historical examples, not the author's portfolio return. Public views do not establish actual positions; past performance does not guarantee future results.".bSmartLocalized)
                    }
                    .font(.subheadline).lineSpacing(4).foregroundStyle(BSmartColor.secondaryText)
                    .padding(.top, 12)
                }
                .accessibilityIdentifier("smart.account.methodology")
            }
            if !updates.isEmpty {
                Divider().overlay(BSmartColor.line)
                DisclosureGroup((updates.contains { $0.settlement?.actualHit == false }
                                 ? "Historical evidence, including misses" : "Historical evidence").bSmartLocalized) {
                    VStack(spacing: 0) {
                        ForEach(updates.sorted { $0.publishedAt > $1.publishedAt }) { update in
                            BSmartDetailNavigationLink(id: "profile-history-\(update.id)") {
                                SmartAccountEvidenceDetailView(update: update)
                            } label: {
                                HStack(spacing: 10) {
                                    BSmartAssetMark(ticker: update.ticker, size: 28)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(update.ticker).font(.subheadline.weight(.semibold))
                                        Text(update.publishedAt.bSmartCompactDate).font(.caption)
                                            .foregroundStyle(BSmartColor.secondaryText)
                                    }
                                    Spacer()
                                    Text((update.settlement?.actualHit == false ? "Historical miss" : update.direction.label).bSmartLocalized)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(update.settlement?.actualHit == false ? BSmartColor.bear : update.direction.color)
                                    Image(systemName: "chevron.right").font(.caption)
                                }.padding(.vertical, 12).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .accessibilityIdentifier("smart.account.history.item.\(update.id)")
                            Divider().overlay(BSmartColor.line)
                        }
                    }.padding(.top, 8)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("smart.account.history")
            }
        }
    }

    private var percentile: String {
        guard let value = account.platformPercentile, value.isFinite, (0...1).contains(value) else { return "--" }
        return "Top \(max(1, Int(ceil(value * 100))))%"
    }

    private func score(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "--" }
        return value.formatted(.number.precision(.fractionLength(0)))
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.bSmartLocalized).font(.caption).foregroundStyle(BSmartColor.secondaryText)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
