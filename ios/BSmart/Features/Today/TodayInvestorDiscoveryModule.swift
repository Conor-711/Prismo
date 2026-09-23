import SwiftUI

struct TodayInvestorDiscoveryModule: View {
    var compact = false
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var portraitTransition
    @State private var portraitSourceID: String?
    @State private var selectedID: String?
    @State private var profileSession: TodayInvestorDiscoverySession?
    @State private var discovery = TodayInvestorDiscovery(accounts: [])

    private var candidates: [TodayInvestorDiscovery.Investor] {
        TodayInvestorPool.arranged(discovery.investors)
    }
    private var activeSelection: TodayInvestorDiscovery.Investor? {
        TodayInvestorDiscovery.selected(selectedID ?? TodayInvestorPool.preferredID, in: candidates)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            controls
            if let investor = activeSelection {
                TodayInvestorDiscoveryPeople(
                    investors: candidates, selectedID: investor.id, compact: compact,
                    transition: portraitTransition
                ) {
                    selectedID = $0.id
                } onOpen: { tapped in
                    portraitSourceID = tapped.id
                    profileSession = .init(investors: candidates, selectedID: tapped.id)
                }
                TodayInvestorDiscoveryFocus(investor: investor, loadsEvidence: true) {
                    portraitSourceID = nil
                    profileSession = .init(investors: candidates, selectedID: investor.id)
                }
            } else if model.isLoading {
                BSmartSkeletonRows(style: .profile, count: 1)
            } else {
                ContentUnavailableView("No ranked investors available", systemImage: "person.2.slash")
                    .frame(minHeight: 240)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.discovery")
        .task { rebuild() }
        .onChange(of: model.smartAccounts) { rebuild() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { rebuild() }
        }
        .fullScreenCover(item: $profileSession) { session in
            TodayInvestorProfileBrowser(session: session)
                .bSmartZoomNavigationTransition(sourceID: portraitSourceID ?? "",
                    in: portraitTransition, enabled: portraitSourceID != nil && !reduceMotion)
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            BSmartDetailNavigationLink(id: "today-investor-directory") {
                SmartHubView()
            } label: {
                HStack(spacing: 8) {
                    TodayHomeSectionHeading(title: "Smart investors", identifier: "discovery.heading")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(BSmartColor.brand)
                        .frame(width: 28, height: 28)
                        .background(BSmartColor.brand.opacity(0.1), in: Circle())
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("discovery.open-directory")
            Spacer(minLength: 0)
            InvestorEducationEntry()
        }
    }

    private func rebuild() {
        discovery = TodayInvestorDiscovery(accounts: model.smartAccounts)
    }
}
