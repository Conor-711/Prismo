import SwiftUI

struct TodayInvestorDiscoveryPeople: View {
    let investors: [TodayInvestorDiscovery.Investor]
    let selectedID: String
    var compact = false
    let transition: Namespace.ID
    let onSelect: (TodayInvestorDiscovery.Investor) -> Void
    let onOpen: (TodayInvestorDiscovery.Investor) -> Void
    @State private var centeredID: String?

    private var index: Int { investors.firstIndex { $0.id == selectedID } ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                let stride = geometry.size.width / 3
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(Array(investors.enumerated()), id: \.element.id) { offset, investor in
                            TodayInvestorPoolPortrait(investor: investor, distance: abs(offset - index), compact: compact,
                                                      cellWidth: stride) {
                                onOpen(investor)
                            }
                            .bSmartMatchedTransitionSource(id: investor.id, in: transition)
                            .frame(width: stride)
                            .id(investor.id)
                            .allowsHitTesting(abs(offset - index) <= 1)
                            .accessibilityHidden(abs(offset - index) > 1)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, (geometry.size.width - stride) / 2, for: .scrollContent)
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $centeredID, anchor: .center)
                .contentShape(Rectangle())
                .clipped()
                .accessibilityIdentifier("discovery.pool")
            }
            .frame(height: compact ? 150 : 164)
        }
        .onChange(of: centeredID) { _, value in
            guard let value, value != selectedID, let investor = investors.first(where: { $0.id == value }) else { return }
            onSelect(investor)
        }
        .onChange(of: investors.map(\.id), initial: true) { _, _ in
            centeredID = selectedID
        }
    }
}

struct TodayInvestorDiscoveryFocus: View {
    @EnvironmentObject private var model: AppModel
    let investor: TodayInvestorDiscovery.Investor
    var profileIdentifier = "discovery.profile"
    var loadsEvidence = false
    var onReceiptVisibilityChange: (Bool) -> Void = { _ in }
    let onOpen: () -> Void
    private var account: SmartAccountProfile { investor.account }
    private var highlight: TodayInvestorDiscoveryHighlight {
        TodayInvestorDiscoveryHighlight(account: account, representatives: model.representativeAccountEvidence(for: account))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button(action: onOpen) {
                    HStack(spacing: 8) {
                        BSmartAvatar(url: account.avatarURL, name: account.name, size: 34)
                        HStack(spacing: 6) {
                            Text(account.name).font(.subheadline.weight(.bold)).lineLimit(1)
                            SmartPlatformMark(platform: account.platform, size: 13)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                    }
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View %@ profile".bSmartLocalized(account.name))
                .accessibilityIdentifier(profileIdentifier)
                TodayInvestorDiscoveryFollow(account: account)
            }
            if loadsEvidence {
                TodayRepresentativeStoryLoader(account: account).id(investor.id)
            } else if highlight.intro != nil {
                TodayInvestorDiscoveryWork(highlight: highlight, onReceiptVisibilityChange: onReceiptVisibilityChange)
            } else {
                HStack(spacing: 8) {
                    Text(account.specialty.bSmartLocalized).foregroundStyle(BSmartColor.secondaryText)
                    Spacer(minLength: 0)
                    let tickers = account.resolvedTopTickers.prefix(2).joined(separator: " / ")
                    if !tickers.isEmpty {
                        Text("Covers %@".bSmartLocalized(tickers)).foregroundStyle(BSmartColor.primaryText)
                    } else if let count = account.settledCalls, count > 0 {
                        Text("%d settled views".bSmartLocalized(count)).foregroundStyle(BSmartColor.secondaryText)
                    }
                }
                .font(.system(size: 11))
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(height: 30)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("discovery.highlight")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(BSmartColor.raisedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(BSmartColor.line, lineWidth: 0.75) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("discovery.focus.\(investor.id)")
    }
}

struct TodayInvestorDiscoveryFollow: View {
    @EnvironmentObject private var model: AppModel
    let account: SmartAccountProfile
    private var followed: Bool { model.isFollowingSmartAccount(account.id) }

    var body: some View {
        Button { model.toggleSmartAccountFollow(account.id) } label: {
            Image(systemName: followed ? "checkmark" : "plus")
                .font(.body.weight(.semibold))
                .foregroundStyle(followed ? BSmartColor.brand : BSmartColor.onAccent)
                .frame(width: 44, height: 44)
                .background(followed ? BSmartColor.brand.opacity(0.1) : BSmartColor.brand)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel((followed ? "Untrack %@" : "Track %@").bSmartLocalized(account.name))
        .accessibilityValue((followed ? "Tracking" : "Not tracking").bSmartLocalized)
        .accessibilityIdentifier("discovery.follow.\(account.id)")
    }
}
