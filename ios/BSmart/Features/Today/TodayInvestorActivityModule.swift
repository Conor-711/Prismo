import SwiftUI

struct TodayInvestorActivityModule: View {
    var body: some View {
        TodayInvestorActivityContent(isPreview: true)
    }
}

struct TodayInvestorActivityCollectionView: View {
    var body: some View {
        ScrollView {
            TodayInvestorActivityContent(isPreview: false)
                .padding(BSmartSpacing.large)
        }
        .background(BSmartColor.ink)
        .navigationTitle("Smart updates".bSmartLocalized)
        .navigationBarTitleDisplayMode(.inline)
        .bSmartDetailPage()
        .bSmartPage()
        .accessibilityIdentifier("smart-updates.collection")
    }
}

private struct TodayInvestorActivityContent: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    let isPreview: Bool
    @State private var investors: [TodayInvestorActivity] = []
    @State private var source: TodayActivityFilter = .all
    @State private var query = ""

    private var displayed: [TodayInvestorActivity] {
        let effectiveSource: TodayActivityFilter = isPreview ? .accounts : source
        let matching = investors.filter { $0.matches(source: effectiveSource, query: query) }
        return isPreview ? TodayInvestorActivity.previewAccounts(from: matching) : matching
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            if isPreview {
                BSmartDetailNavigationLink(id: "today-smart-updates-library") {
                    TodayInvestorActivityCollectionView()
                } label: {
                    TodayEditorialSectionTitle(title: "Smart updates", showsDisclosure: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("today.smart-updates.title")
            }
            if !isPreview {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(BSmartColor.tertiaryText)
                    TextField("Search investor or ticker".bSmartLocalized, text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("smart-updates.search")
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .tint(BSmartColor.secondaryText)
                            .accessibilityLabel("Clear search".bSmartLocalized)
                    }
                }
                .padding(12)
                .background(BSmartKeyboardInputRegion())
                .background(BSmartColor.surface, in: RoundedRectangle(cornerRadius: 8))
            }
            if !isPreview {
                Picker("Sources".bSmartLocalized, selection: $source) {
                    ForEach(TodayActivityFilter.allCases) { filter in
                        Text(filter == .all ? "All sources".bSmartLocalized : filter.label).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("smart-updates.source-filter")
            }

            if model.isLoading && investors.isEmpty {
                BSmartSkeletonRows(style: .feed, count: isPreview ? 2 : 4)
            } else if displayed.isEmpty {
                Label("No matching updates in the last 30 days".bSmartLocalized, systemImage: "text.bubble")
                    .font(.subheadline)
                    .foregroundStyle(BSmartColor.secondaryText)
                    .padding(.vertical, 24)
                    .accessibilityIdentifier("smart-updates.empty")
            } else {
                ForEach(displayed) { TodayInvestorActivityCard(investor: $0) }
            }
        }
        .onAppear(perform: rebuild)
        .onChange(of: model.smartAccountUpdates) { rebuild() }
        .onChange(of: model.smartMoneyMovements) { rebuild() }
        .onChange(of: scenePhase) { if scenePhase == .active { rebuild() } }
    }

    private func rebuild() {
        investors = TodayInvestorActivity.groups(accountUpdates: model.smartAccountUpdates,
                                                  moneyMovements: model.smartMoneyMovements)
    }
}

struct TodayInvestorActivityTimelineView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    let investorID: String
    @State private var investor: TodayInvestorActivity?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if let investor {
                    TodayInvestorActivityHeader(investor: investor)
                    ForEach(investor.activities) { activity in
                        Divider().overlay(BSmartColor.line)
                        TodayInvestorActivityEntry(activity: activity, isTimeline: true)
                    }
                } else {
                    Label("No matching updates in the last 30 days".bSmartLocalized, systemImage: "text.bubble")
                        .foregroundStyle(BSmartColor.secondaryText)
                }
            }
            .padding(BSmartSpacing.large)
        }
        .background(BSmartColor.ink)
        .navigationTitle(investor?.name ?? "Smart updates".bSmartLocalized)
        .navigationBarTitleDisplayMode(.inline)
        .bSmartDetailPage()
        .bSmartPage()
        .accessibilityIdentifier("smart-updates.timeline")
        .refreshable { await model.refreshLiveIntelligence() }
        .onAppear(perform: rebuild)
        .onChange(of: model.smartAccountUpdates) { rebuild() }
        .onChange(of: model.smartMoneyMovements) { rebuild() }
        .onChange(of: scenePhase) { if scenePhase == .active { rebuild() } }
    }

    private func rebuild() {
        investor = TodayInvestorActivity.groups(accountUpdates: model.smartAccountUpdates,
                                                moneyMovements: model.smartMoneyMovements)
            .first { $0.id == investorID }
    }
}
