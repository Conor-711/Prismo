import SwiftUI

struct TodayMarketActivityView: View {
    let packages: [TodayViewpointPackage]
    let opportunities: [TodayAlphaOpportunity]
    @Namespace private var consensusTransition
    @Namespace private var alphaTransition

    private var previewOpportunities: [TodayAlphaOpportunity] {
        opportunities.filter { $0.kind == .smartAccount }
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            BSmartDetailNavigationLink(id: "today-consensus-library") {
                TodayConsensusCollectionView(packages: packages)
            } label: {
                TodayEditorialSectionTitle(title: "Trending Tickers", showsDisclosure: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("today.consensus.title")

            if packages.isEmpty { emptyState }
            VStack(spacing: 12) {
                ForEach(Array(packages.prefix(2).enumerated()), id: \.element.id) { index, package in
                    NavigationLink {
                        TodayViewpointPackageDetailView(package: package, style: index % 2)
                            .bSmartZoomNavigationTransition(sourceID: package.id, in: consensusTransition)
                    } label: {
                        TodayViewpointPackageCard(package: package, style: index % 2, width: nil, isStacked: true)
                            .bSmartMatchedTransitionSource(id: package.id, in: consensusTransition)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("today.viewpoint-package.\(package.ticker.lowercased())")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("today.viewpoint-preview")

            BSmartDetailNavigationLink(id: "today-alpha-library") {
                TodayAlphaCollectionView(opportunities: opportunities)
            } label: {
                TodayEditorialSectionTitle(title: "Alpha Tickers", showsDisclosure: true)
            }
            .buttonStyle(.plain)
            .padding(.top, BSmartSpacing.large)
            .accessibilityIdentifier("today.alpha.title")

            if previewOpportunities.isEmpty { emptyState }
            ForEach(previewOpportunities.prefix(2)) { opportunity in
                NavigationLink {
                    TodayAlphaOpportunityDetailView(opportunity: opportunity)
                        .bSmartZoomNavigationTransition(sourceID: opportunity.id, in: alphaTransition)
                } label: {
                    TodayAlphaDiscoveryRow(opportunity: opportunity)
                        .bSmartMatchedTransitionSource(id: opportunity.id, in: alphaTransition)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("today.smart-alpha.\(opportunity.kind.rawValue).\(opportunity.ticker.lowercased())")
            }
        }
    }

    private var emptyState: some View {
        Label("No matching updates in the last 30 days".bSmartLocalized, systemImage: "text.bubble")
            .font(.subheadline)
            .foregroundStyle(BSmartColor.secondaryText)
            .padding(.vertical, 24)
    }
}

private struct TodayAlphaDiscoveryRow: View {
    let opportunity: TodayAlphaOpportunity

    private var accent: Color {
        opportunity.kind == .smartAccount ? BSmartColor.brand : BSmartColor.sky
    }

    private var sourceRank: String {
        let key: String?
        switch opportunity.source {
        case let .account(updates): key = updates.first?.authorId.lowercased()
        case let .money(movements): key = movements.first?.accountId.lowercased()
        }
        return key.flatMap { opportunity.sourceRankLabels[$0] } ?? opportunity.localizedSourceLabel
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            BSmartAssetMark(ticker: opportunity.ticker, size: 34)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(opportunity.ticker)
                        .font(.headline.weight(.bold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(sourceRank)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                }
                if let headline = opportunity.sourceHeadlines.first {
                    Text(headline.text)
                        .font(.subheadline.weight(.medium))
                        .lineSpacing(3)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                source
            }
        }
        .foregroundStyle(BSmartColor.primaryText)
        .multilineTextAlignment(.leading)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(BSmartColor.line).frame(height: 0.5) }
        .contentShape(Rectangle())
    }

    @ViewBuilder private var source: some View {
        switch opportunity.source {
        case let .account(updates):
            if let update = updates.first {
                HStack(spacing: 6) {
                    BSmartAvatar(url: update.authorAvatarURL, name: update.authorName, size: 24)
                        .bSmartSubjectDestination(update)
                    SmartPlatformMark(platform: update.platform, size: 12)
                    sourceLabel(update.authorName, date: update.publishedAt)
                }
            }
        case let .money(movements):
            if let movement = movements.first {
                HStack(spacing: 6) {
                    BSmartSmartMoneyAvatar(identity: movement.publicIdentity, size: 24)
                        .bSmartSubjectDestination(movement)
                    SmartPlatformMark(platform: "Hyperliquid", size: 12)
                    sourceLabel(movement.publicIdentity.displayName, date: movement.observedAt)
                }
            }
        }
    }

    private func sourceLabel(_ name: String, date: Date) -> some View {
        HStack(spacing: 6) {
            Text(name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(date.bSmartRelativeTimestamp)
                .font(.caption2)
                .foregroundStyle(BSmartColor.tertiaryText)
                .lineLimit(1)
                .layoutPriority(1)
        }
    }
}
