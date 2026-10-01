import SwiftUI

private enum AbilityLeaderboardFilter: Hashable, CaseIterable {
    case all, platform, politician, celebrity, institution

    var kind: AbilityActorKind? {
        switch self {
        case .all: nil
        case .platform: .platform
        case .politician: .politician
        case .celebrity: .celebrity
        case .institution: .institution
        }
    }

    var title: String { kind?.title ?? "All" }

    var imageName: String {
        switch self {
        case .all: "LeaderboardFilterAll"
        case .platform: "LeaderboardFilterPlatform"
        case .politician: "LeaderboardFilterPolitician"
        case .celebrity: "LeaderboardFilterCelebrity"
        case .institution: "LeaderboardFilterInstitution"
        }
    }

    var subtitle: String {
        switch self {
        case .all: "Every source"
        case .platform: "Social and bSmart"
        case .politician: "Public officials"
        case .celebrity: "Public investors"
        case .institution: "Funds and firms"
        }
    }
}

struct AbilityLeaderboardView: View {
    @EnvironmentObject private var model: AppModel
    @State private var filter = AbilityLeaderboardFilter.all
    let refresh: Int
    var snapshotOverride: InvestorAbilityLeaderboard? = nil

    private var presentedSnapshot: InvestorAbilityLeaderboard {
        if let snapshotOverride { return snapshotOverride }
        if let research = InvestorAbilityLeaderboard.bundledResearch {
            var subjects = Dictionary(uniqueKeysWithValues: TodaySubjectFeedSnapshot.bundled.subjects.map { ($0.id, $0) })
            for subject in model.subjectActivitySnapshot.subjects { subjects[subject.id] = subject }
            return research.replacingSubjectResearch(with: Array(subjects.values)).balancedMock()
        }
        return .mock(accounts: model.smartAccounts, subjects: model.subjectActivitySnapshot.subjects).balancedMock()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            filters
            published(presentedSnapshot)
        }
        .padding(.top, 8)
        .padding(.bottom, 110)
        .accessibilityIdentifier("discover.ability-leaderboard")
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(AbilityLeaderboardFilter.allCases, id: \.self) { option in
                    Button {
                        filter = option
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Image(option.imageName)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 160, height: 100)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(filter == option ? BSmartColor.brand : BSmartColor.line,
                                                      lineWidth: filter == option ? 2 : 0.75)
                                }
                            Text(option.title.bSmartLocalized)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(filter == option ? BSmartColor.primaryText : BSmartColor.secondaryText)
                                .lineLimit(1)
                            Text(option.subtitle.bSmartLocalized)
                                .font(.caption)
                                .foregroundStyle(BSmartColor.tertiaryText)
                                .lineLimit(1)
                        }
                        .frame(width: 160, alignment: .leading)
                    }
                    .buttonStyle(.bSmartPlain)
                    .accessibilityLabel(option.title.bSmartLocalized)
                    .accessibilityAddTraits(filter == option ? .isSelected : [])
                    .accessibilityIdentifier("discover.ability.filter.\(option)")
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private func published(_ snapshot: InvestorAbilityLeaderboard) -> some View {
        let visible = snapshot.items.filter { filter.kind == nil || $0.actorKind == filter.kind }
        let scored = visible.filter { $0.score != nil }
        let leaders = Array(scored.prefix(3))
        return LazyVStack(alignment: .leading, spacing: 0) {
            if scored.isEmpty {
                state(snapshot.isMock
                      ? (filter == .platform && model.smartAccounts.isEmpty
                         ? "Subjects are loading" : "No subjects in this category")
                      : "No scored subjects yet",
                      symbol: "chart.bar.xaxis")
            } else {
                if let leader = leaders.first {
                    rankingLink(for: leader, isMock: snapshot.isMock) {
                        AbilityLeaderboardLeader(item: leader, isMock: snapshot.isMock, isResearch: snapshot.isResearch)
                    }
                }
                if leaders.count > 1 {
                    HStack(spacing: 8) {
                        ForEach(leaders.dropFirst()) { item in
                            rankingLink(for: item, isMock: snapshot.isMock) {
                                AbilityLeaderboardContender(item: item, isMock: snapshot.isMock, isResearch: snapshot.isResearch)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
                if scored.count > 3 {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Full ranking".bSmartLocalized)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(BSmartColor.primaryText)
                        Spacer()
                        Text("\(scored.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(BSmartColor.secondaryText)
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 8)
                }
            }
            ForEach(scored.dropFirst(3)) { item in
                rankingLink(for: item, isMock: snapshot.isMock) {
                    AbilityLeaderboardRow(item: item, isMock: snapshot.isMock, isResearch: snapshot.isResearch)
                }
                Divider().overlay(BSmartColor.line)
            }
            Text((snapshot.isMock ? "Mock scores for preview only; not actual investment results or return forecasts" :
                  snapshot.isResearch ? "Research estimate · not a forecast" : "Historical score, not a forecast").bSmartLocalized)
                .font(.caption).foregroundStyle(BSmartColor.tertiaryText)
                .padding(.top, 18)
                .accessibilityIdentifier("discover.ability.mock-disclaimer")
        }
    }

    private func rankingLink<Label: View>(
        for item: InvestorAbilityItem,
        isMock: Bool,
        @ViewBuilder label: () -> Label
    ) -> some View {
        NavigationLink { AbilityScoreDetailView(item: item, asOf: presentedSnapshot.asOf,
                                                isMock: isMock, isResearch: presentedSnapshot.isResearch) } label: {
            label()
        }
        .buttonStyle(.bSmartPlain)
        .accessibilityIdentifier("discover.ability.actor.\(item.id)")
    }

    private func state(_ title: String, symbol: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.title2)
            Text(title.bSmartLocalized).font(.subheadline)
        }
        .foregroundStyle(BSmartColor.secondaryText)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 72)
    }
}

private struct AbilityLeaderboardLeader: View {
    let item: InvestorAbilityItem
    let isMock: Bool
    let isResearch: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("#\(item.rank ?? 1)")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(BSmartColor.gold)
                Spacer()
                Text(item.actorKind.title.bSmartLocalized.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(BSmartColor.secondaryText)
                    .lineLimit(1)
            }
            HStack(alignment: .bottom, spacing: 12) {
                AbilityActorAvatar(item: item, size: 60)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.displayName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(BSmartColor.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let platform = item.platform {
                        Text(platform)
                            .font(.caption)
                            .foregroundStyle(BSmartColor.secondaryText)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(item.scoreLabel)
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(AbilityScoreTone.color(for: item))
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                    Text((isResearch ? "Research score · pp" : isMock ? "Mock points" : "Score · pp").bSmartLocalized)
                        .font(.caption2)
                        .foregroundStyle(BSmartColor.secondaryText)
                }
            }
            if isResearch { AbilityResearchMetrics(item: item) }
        }
        .padding(16)
        .background(BSmartColor.surface, in: RoundedRectangle(cornerRadius: BSmartRadius.card))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(BSmartColor.gold)
                .frame(width: 3)
                .padding(.vertical, 16)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct AbilityLeaderboardContender: View {
    let item: InvestorAbilityItem
    let isMock: Bool
    let isResearch: Bool

    private var rankColor: Color { item.rank == 2 ? BSmartColor.sky : BSmartColor.brand }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("#\(item.rank ?? 0)")
                    .font(.headline.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(rankColor)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(BSmartColor.tertiaryText)
            }
            HStack(spacing: 8) {
                AbilityActorAvatar(item: item, size: 34)
                Text(item.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BSmartColor.primaryText)
                    .lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.scoreLabel)
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AbilityScoreTone.color(for: item))
                    .lineLimit(1)
                Text((isResearch ? "Research score · pp" : isMock ? "Mock points" : "Score · pp").bSmartLocalized)
                    .font(.caption2)
                    .foregroundStyle(BSmartColor.secondaryText)
            }
            if isResearch { AbilityResearchMetrics(item: item) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(BSmartColor.surface, in: RoundedRectangle(cornerRadius: BSmartRadius.card))
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 2)
                .fill(rankColor)
                .frame(height: 2)
                .padding(.horizontal, 12)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private enum AbilityScoreTone {
    static func color(for item: InvestorAbilityItem) -> Color {
        guard let score = item.score else { return BSmartColor.tertiaryText }
        return score < 0 ? BSmartColor.bear : BSmartColor.brand
    }
}

private struct AbilityLeaderboardRow: View {
    let item: InvestorAbilityItem
    let isMock: Bool
    let isResearch: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(item.rank.map { "\($0)" } ?? "—")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(item.rank == nil ? BSmartColor.tertiaryText : BSmartColor.primaryText)
                .frame(width: 30, alignment: .leading)
            AbilityActorAvatar(item: item, size: 42)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName).font(.body.weight(.semibold))
                    .foregroundStyle(BSmartColor.primaryText).lineLimit(1)
                Text(item.actorKind.title.bSmartLocalized + (item.platform.map { " · \($0)" } ?? ""))
                    .font(.caption).foregroundStyle(BSmartColor.secondaryText).lineLimit(1)
                if isResearch { AbilityResearchMetrics(item: item) }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(item.scoreLabel)
                    .font(.headline.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(AbilityScoreTone.color(for: item))
                if item.score != nil {
                    Text((isResearch ? "Research · pp" : isMock ? "Mock points" : "Score · pp").bSmartLocalized)
                        .font(.caption2).foregroundStyle(BSmartColor.tertiaryText)
                }
            }
            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                .foregroundStyle(BSmartColor.tertiaryText)
        }
        .frame(minHeight: 72)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct AbilityScoreDetailView: View {
    let item: InvestorAbilityItem
    let asOf: Date?
    let isMock: Bool
    let isResearch: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 14) {
                    AbilityActorAvatar(item: item, size: 56)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.displayName).font(.title2.weight(.bold))
                        Text(item.actorKind.title.bSmartLocalized)
                            .foregroundStyle(BSmartColor.secondaryText)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text((isResearch ? "Research score" : isMock ? "Mock score" : "Score").bSmartLocalized).font(.subheadline)
                        .foregroundStyle(BSmartColor.secondaryText)
                    Text(item.scoreLabel)
                        .font(.system(size: 42, weight: .semibold)).monospacedDigit()
                    if isMock {
                        Text("Mock scores for preview only; not actual investment results or return forecasts".bSmartLocalized)
                            .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                    } else if isResearch {
                        Text("Unaudited research estimate; not a forecast of investor returns".bSmartLocalized)
                            .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                    } else if item.score != nil {
                        Text("Annualized adjusted follower-return percentage points".bSmartLocalized)
                            .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                    } else {
                        Text(item.status.title.bSmartLocalized)
                            .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                    }
                }
                if !isMock {
                    Divider().overlay(BSmartColor.line)
                    if isResearch {
                        metric("Win rate", value: item.winRate.map {
                            $0.formatted(.percent.precision(.fractionLength(1)))
                        } ?? "—")
                        if let observations = item.winRateObservations {
                            metric("Win-rate observations", value: observations.formatted())
                        }
                        metric(item.followReturnMethod == "open_position_equal_weight_absolute"
                               ? "Follow return" : item.followReturnMethod == "directional_30d_proxy"
                               ? "Follow return · directional proxy" : "Follow return · 30d", value: item.followReturn.map {
                            $0.formatted(.percent.precision(.fractionLength(1)).sign(strategy: .always()))
                        } ?? "—")
                    }
                    metric("Observation days", value: "\(item.observedCalendarDays)")
                    metric("Independent decision days", value: "\(item.independentDecisionDays)")
                    metric("Priced coverage", value: item.pricedCoverage.formatted(.percent.precision(.fractionLength(0))))
                    if let asOf { metric("As of", value: asOf.formatted(date: .abbreviated, time: .omitted)) }
                    Text((isResearch ? "Research estimate · not a forecast" : "Historical score, not a forecast").bSmartLocalized)
                        .font(.footnote).foregroundStyle(BSmartColor.tertiaryText)
                }
            }
            .padding(20)
        }
        .navigationTitle(item.displayName).navigationBarTitleDisplayMode(.inline)
        .bSmartDetailPage().bSmartPage()
    }

    private func metric(_ title: String, value: String) -> some View {
        HStack {
            Text(title.bSmartLocalized).foregroundStyle(BSmartColor.secondaryText)
            Spacer()
            Text(value).foregroundStyle(BSmartColor.primaryText)
        }
        .font(.subheadline)
    }
}

private struct AbilityActorAvatar: View {
    @EnvironmentObject private var model: AppModel
    let item: InvestorAbilityItem
    let size: CGFloat

    private var resolvedURL: URL? {
        item.avatarURL
            ?? model.smartAccounts.first(where: { $0.id == item.actorId })?.avatarURL
            ?? model.smartAccountUpdates.first(where: { $0.authorId == item.actorId })?.authorAvatarURL
    }

    var body: some View {
        Group {
            if item.actorKind == .platform && resolvedURL == nil {
                SmartPlatformMark(platform: item.platform ?? "bsmart", size: size)
            } else {
                BSmartAvatar(
                    url: resolvedURL,
                    name: item.displayName,
                    size: size,
                    fallbackSymbol: item.actorKind == .institution ? "building.2.fill" : "person.fill",
                    bundledAssetName: item.actorKind == .platform ? nil
                        : TodaySubjectProfile.avatarAssetName(for: item.actorId),
                    isOrganization: item.actorKind == .institution,
                    cornerRadius: min(8, size * 0.18)
                )
            }
        }
    }
}

private struct AbilityResearchMetrics: View {
    let item: InvestorAbilityItem

    var body: some View {
        HStack(spacing: 8) {
            Text("Win rate".bSmartLocalized + " " + (item.winRate.map {
                $0.formatted(.percent.precision(.fractionLength(0)))
            } ?? "—"))
            Text((item.followReturnMethod == "open_position_equal_weight_absolute"
                  ? "Follow return" : item.followReturnMethod == "directional_30d_proxy"
                  ? "Directional proxy" : "Follow return").bSmartLocalized + " " + (item.followReturn.map {
                $0.formatted(.percent.precision(.fractionLength(1)).sign(strategy: .always()))
            } ?? "—"))
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(BSmartColor.secondaryText)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
}
