import SwiftUI

struct NativeTraderDetailSections: View {
    @EnvironmentObject private var account: AccountAccessStore
    @ObservedObject var store: NativeTraderDetailStore
    let profileID: UUID
    let client: NativeTraderDetailClient
    let demo: TradeFeedDemoData?
    let refresh: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            if demo == nil {
                portfolio
                if store.socialFailed {
                    Button("Follow status unavailable. Retry".bSmartLocalized) {
                        Task {
                            guard let viewerID = account.identity?.id else { return }
                            await store.retrySocial(viewerID, client: client)
                        }
                    }
                    .buttonStyle(.bSmartSecondary)
                }
            }
            Rectangle().fill(BSmartColor.line).frame(height: 0.5)
            VStack(alignment: .leading, spacing: 16) {
                Text("Trade history".bSmartLocalized).font(.title3.weight(.bold))
                TradeFeedContents(store: store.trades, reload: refresh, loadMore: {
                    await store.loadTrades(profileID, client: client, reset: false, demo: demo)
                }, demo: demo)
            }
            .accessibilityIdentifier("smart.account.trade-history")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("smart.account.live-portfolio")
    }

    @ViewBuilder private var portfolio: some View {
        if let portfolio = store.portfolio {
            if portfolio.status == .ready {
                FeedPublicPortfolioView(portfolio: portfolio)
                FeedPublicPositionsView(positions: portfolio.positions)
            } else {
                Label("No linked trading wallet".bSmartLocalized, systemImage: "wallet.pass")
                    .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
            }
        } else if store.portfolioFailed {
            HStack {
                Text("On-chain account unavailable".bSmartLocalized)
                    .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                Spacer(minLength: 8)
                Button("Retry".bSmartLocalized) {
                    Task { await store.retryPortfolio(profileID, client: client) }
                }
                .buttonStyle(.bSmartSecondary)
                .accessibilityIdentifier("smart.account.portfolio.retry")
            }
        } else {
            BSmartSkeletonRows(style: .feed, count: 2)
        }
    }
}
