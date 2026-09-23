import SwiftUI

struct TodayInvestorDiscoveryPage: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TodayInvestorDirectoryContent(discovery: TodayInvestorDiscovery(accounts: model.smartAccounts))
            .bSmartDetailPage()
    }
}

// Education presents a platform-scoped directory in its own modal navigation stack.
struct TodayInvestorDiscoveryDirectory: View {
    @Environment(\.dismiss) private var dismiss
    let discovery: TodayInvestorDiscovery
    let sector: String?

    var body: some View {
        NavigationStack {
            TodayInvestorDirectoryContent(discovery: discovery, sector: sector)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("Close".bSmartLocalized)
                            .accessibilityIdentifier("discovery.directory.close")
                    }
                }
        }
    }
}

private struct TodayInvestorDirectoryContent: View {
    @EnvironmentObject private var model: AppModel
    let discovery: TodayInvestorDiscovery
    @State private var sector: String?
    @State private var platform: String?
    @State private var query = ""
    @State private var followingOnly = false
    @State private var profileSession: TodayInvestorDiscoverySession?

    init(discovery: TodayInvestorDiscovery, sector: String? = nil) {
        self.discovery = discovery
        _sector = State(initialValue: sector)
    }

    private var platforms: [String] {
        Set(discovery.investors.map { $0.account.platform }).sorted()
    }

    private var candidates: [TodayInvestorDiscovery.Investor] {
        discovery.candidates(sector: sector, query: query, localize: { $0.bSmartLocalized })
            .filter { platform == nil || $0.account.platform == platform }
            .filter { !followingOnly || model.isFollowingSmartAccount($0.account.id) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                filters
                HStack {
                    Text("%d investors".bSmartLocalized(candidates.count))
                        .foregroundStyle(BSmartColor.secondaryText)
                    Spacer()
                    Text("Top 25%")
                        .foregroundStyle(BSmartColor.brand)
                }
                .font(.caption.weight(.semibold))
                .accessibilityIdentifier("discovery.directory.count")

                if candidates.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
                ForEach(candidates) { investor in
                    TodayInvestorDiscoveryFocus(investor: investor, profileIdentifier: "discovery.directory.profile") {
                        profileSession = .init(investors: candidates, selectedID: investor.id)
                    }
                }
            }
            .padding(BSmartSpacing.large)
        }
        .background(BSmartColor.ink)
        .navigationTitle("Discover investors".bSmartLocalized)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Investor, sector or ticker".bSmartLocalized)
        .bSmartPage()
        .accessibilityIdentifier("discovery.directory")
        .fullScreenCover(item: $profileSession) { TodayInvestorProfileBrowser(session: $0) }
    }

    private var filters: some View {
        VStack(spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { platformMenu; sectorMenu }
                VStack(spacing: 10) { platformMenu; sectorMenu }
            }
            Toggle("Following only".bSmartLocalized, isOn: $followingOnly)
                .font(.subheadline)
                .tint(BSmartColor.brand)
                .accessibilityIdentifier("discovery.directory.following")
        }
    }

    private var platformMenu: some View {
        Menu {
            Picker("Platform".bSmartLocalized, selection: $platform) {
                Text("All platforms".bSmartLocalized).tag(nil as String?)
                ForEach(platforms, id: \.self) { value in
                    Text(value).tag(Optional(value))
                }
            }
        } label: {
            filterLabel(platform ?? "All platforms", symbol: "globe")
        }
        .accessibilityIdentifier("discovery.directory.platform")
    }

    private var sectorMenu: some View {
        Menu {
            Picker("Sector".bSmartLocalized, selection: $sector) {
                Text("All sectors".bSmartLocalized).tag(nil as String?)
                ForEach(discovery.sectors, id: \.self) { value in
                    Text(value.bSmartLocalized).tag(Optional(value))
                }
            }
        } label: {
            filterLabel(sector ?? "All sectors", symbol: "square.grid.2x2")
        }
        .accessibilityIdentifier("discovery.directory.sector")
    }

    private func filterLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
            Text(title.bSmartLocalized).fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
            Image(systemName: "chevron.down").font(.caption2.weight(.bold))
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(BSmartColor.primaryText)
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(BSmartColor.surface, in: RoundedRectangle(cornerRadius: 8))
    }
}
