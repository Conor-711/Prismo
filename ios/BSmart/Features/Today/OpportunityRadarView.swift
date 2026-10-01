import SwiftUI

struct OpportunityRadarView: View {
    @EnvironmentObject private var model: AppModel

    private var visibleSignals: [PortfolioSignal] {
        model.opportunitySignals.filter(\.isVisibleInProduct)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: BSmartSpacing.xLarge) {
                intro

                if visibleSignals.isEmpty {
                    ContentUnavailableView {
                        Label("No qualified opportunities", systemImage: "scope")
                    } description: {
                        Text("No untracked stock currently meets bSmart's importance and evidence thresholds.")
                    }
                    .frame(maxWidth: .infinity, minHeight: 320)
                } else {
                    BSmartSectionHeader(
                        title: "Outside your portfolio",
                        detail: "\(visibleSignals.count) to investigate"
                    )

                    ForEach(Array(visibleSignals.enumerated()), id: \.element.id) { index, signal in
                        BSmartDetailNavigationLink(id: "opportunity-\(signal.id)") {
                            EventDetailView(signal: signal)
                        } label: {
                            EventCard(
                                signal: signal,
                                personalization: model.personalization(for: signal),
                                userState: model.signalUserState(for: signal.id),
                                isPriority: index == 0
                            )
                        }
                        .buttonStyle(.bSmartPlain)
                        .accessibilityIdentifier("opportunity-radar.signal.\(signal.ticker)")
                        .simultaneousGesture(TapGesture().onEnded {
                            model.markSignalRead(signal.id)
                        })
                    }
                }
            }
            .padding(BSmartSpacing.large)
            .padding(.bottom, BSmartSpacing.xLarge)
        }
        .background(BSmartColor.ink)
        .navigationTitle("Opportunities")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("opportunity-radar.screen")
        .bSmartDetailPage()
        .bSmartPage()
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.small) {
            Label("Qualified changes, not market noise", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(BSmartColor.gold)
            Text(BSmartProductVisibility.onchainSmartMoney
                ? "Only important Smart Account or Smart Money changes from bSmart's covered stock universe appear here. Add a stock to your watchlist to make future changes personal."
                : "Recent Smart Account views outside your portfolio appear here. Add a stock to your watchlist to personalize updates.")
                .font(.subheadline)
                .foregroundStyle(BSmartColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .bSmartSurface()
    }
}
