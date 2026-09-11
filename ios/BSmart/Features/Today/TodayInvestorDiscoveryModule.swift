import SwiftUI

struct TodayInvestorDiscoveryModule: View {
    var compact = false
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var sector: String?
    @State private var selectedID: String?
    @State private var showsDirectory = false
    @State private var profileSession: TodayInvestorDiscoverySession?
    @State private var discovery = TodayInvestorDiscovery(accounts: [])

    private var candidates: [TodayInvestorDiscovery.Investor] {
        TodayInvestorPool.arranged(discovery.candidates(sector: sector))
    }
    private var activeSelection: TodayInvestorDiscovery.Investor? {
        TodayInvestorDiscovery.selected(selectedID ?? TodayInvestorPool.preferredID, in: candidates)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            controls
            sectors
            if let investor = activeSelection {
                TodayInvestorDiscoveryPeople(
                    investors: candidates, selectedID: investor.id, compact: compact
                ) {
                    selectedID = $0.id
                }
                .id(sector)
                TodayInvestorDiscoveryFocus(investor: investor, loadsEvidence: true) {
                    profileSession = .init(investors: candidates, selectedID: investor.id)
                }
            } else if model.isLoading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 240)
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
        .sheet(isPresented: $showsDirectory) {
            TodayInvestorDiscoveryDirectory(discovery: discovery, sector: sector)
        }
        .fullScreenCover(item: $profileSession) { session in
            TodayInvestorProfileBrowser(session: session)
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            TodayHomeSectionHeading(title: "Smart investors", symbol: "person.2.fill",
                                    accent: BSmartColor.brand, identifier: "discovery.heading")
            Spacer(minLength: 0)
            Text("Top 25%")
                .font(.caption.weight(.bold))
                .foregroundStyle(BSmartColor.brand)
                .accessibilityLabel("Platform Top 25%".bSmartLocalized)
            Button { showsDirectory = true } label: {
                Image(systemName: "magnifyingglass").font(.body.weight(.medium))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(BSmartColor.secondaryText)
            .accessibilityLabel("Search investors".bSmartLocalized)
            .accessibilityIdentifier("discovery.search")
        }
    }

    private var sectors: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                sectorButton(nil)
                ForEach(discovery.sectors, id: \.self) { sectorButton($0) }
            }
        }
        .accessibilityIdentifier("discovery.sectors")
    }

    private func sectorButton(_ value: String?) -> some View {
        Button { sector = value } label: {
            Text((value ?? "All sectors").bSmartLocalized)
                .font(.caption.weight(sector == value ? .bold : .medium))
                .foregroundStyle(sector == value ? BSmartColor.brand : BSmartColor.secondaryText)
                .frame(minHeight: 44)
                .overlay(alignment: .bottom) {
                    if sector == value { Rectangle().fill(BSmartColor.brand).frame(height: 2) }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(sector == value ? .isSelected : [])
        .accessibilityIdentifier("discovery.sector.\(value ?? "all")")
    }

    private func rebuild() {
        discovery = TodayInvestorDiscovery(accounts: model.smartAccounts)
        if let sector, !discovery.sectors.contains(sector) { self.sector = nil }
    }
}
