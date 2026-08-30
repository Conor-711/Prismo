import SwiftUI

struct OpportunityRadarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: BSmartSpacing.xLarge) {
                intro

                if model.opportunitySignals.isEmpty {
                    ContentUnavailableView {
                        Label("No qualified opportunities", systemImage: "scope")
                    } description: {
                        Text("No untracked stock currently meets bSmart's importance and evidence thresholds.")
                    }
                    .frame(maxWidth: .infinity, minHeight: 320)
                } else {
                    BSmartSectionHeader(
                        title: "Outside your portfolio",
                        detail: "\(model.opportunitySignals.count) to investigate"
                    )

                    ForEach(Array(model.opportunitySignals.enumerated()), id: \.element.id) { index, signal in
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
                        .buttonStyle(.plain)
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
        .bSmartPage()
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.small) {
            Label("Qualified changes, not market noise", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(BSmartColor.gold)
            Text("Only important Smart Account or Smart Money changes from bSmart's covered stock universe appear here. Add a stock to your watchlist to make future changes personal.")
                .font(.subheadline)
                .foregroundStyle(BSmartColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .bSmartSurface()
    }
}
