import SwiftUI

struct TodayInvestorDiscoveryDirectory: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let discovery: TodayInvestorDiscovery
    let sector: String?
    @State private var query = ""
    @State private var followingOnly = false
    @State private var profileSession: TodayInvestorDiscoverySession?

    private var candidates: [TodayInvestorDiscovery.Investor] {
        discovery.candidates(sector: sector, query: query, localize: { $0.bSmartLocalized })
            .filter { !followingOnly || model.isFollowingSmartAccount($0.account.id) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    HStack {
                        Text((sector ?? "All sectors").bSmartLocalized)
                            .foregroundStyle(BSmartColor.secondaryText)
                        Spacer()
                        Text("%d investors".bSmartLocalized(candidates.count))
                            .foregroundStyle(BSmartColor.tertiaryText)
                    }
                    .font(.caption)
                    Toggle("Following only".bSmartLocalized, isOn: $followingOnly)
                        .font(.subheadline)
                        .accessibilityIdentifier("discovery.directory.following")
                    if candidates.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                    ForEach(candidates) { investor in
                        TodayInvestorDiscoveryFocus(investor: investor, profileIdentifier: "discovery.directory.profile") {
                            profileSession = .init(investors: candidates, selectedID: investor.id)
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Discover investors".bSmartLocalized)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Investor, sector or ticker".bSmartLocalized)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close".bSmartLocalized)
                        .accessibilityIdentifier("discovery.directory.close")
                }
            }
            .bSmartPage()
            .accessibilityIdentifier("discovery.directory")
            .fullScreenCover(item: $profileSession) { TodayInvestorProfileBrowser(session: $0) }
        }
    }
}
