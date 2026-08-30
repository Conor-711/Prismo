import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var page = 0
    @State private var isShowingBrokerageConnections = false

    private let pageCount = 3

    var body: some View {
        VStack(spacing: 0) {
            topBar

            TabView(selection: $page) {
                rankingPage.tag(0)
                productPage.tag(1)
                setupPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(BSmartMotion.standard, value: page)

            bottomBar
        }
        .padding(.horizontal, BSmartSpacing.large)
        .padding(.top, BSmartSpacing.small)
        .padding(.bottom, BSmartSpacing.small)
        .background(BSmartColor.ink.ignoresSafeArea())
        .sheet(isPresented: $isShowingBrokerageConnections) {
            BrokerageConnectionView(autoDismissAfterConnection: true)
                .environmentObject(model)
        }
        .overlay(alignment: .topLeading) {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("onboarding.screen")
                .allowsHitTesting(false)
        }
        .bSmartPage()
    }

    private var topBar: some View {
        HStack {
            BSmartWordmark(fontSize: 20)
            Spacer()
            if page < pageCount - 1 {
                Button("Skip".bSmartLocalized) {
                    withAnimation(BSmartMotion.standard) { page = pageCount - 1 }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(BSmartColor.tertiaryText)
                .accessibilityIdentifier("onboarding.skip")
            }
        }
        .frame(height: 36)
    }

    private var rankingPage: some View {
        OnboardingPageFrame(
            eyebrow: "SMART RANKS, EARNED OVER TIME",
            title: "Know who is worth your attention",
            lead: "Every public call waits for the market to settle. Rankings update from results, sample confidence and recency."
        ) {
            VStack(spacing: BSmartSpacing.medium) {
                OnboardingPriceEvidenceChart(
                    accounts: Array(accountCandidates.prefix(2)),
                    money: moneyCandidates.first
                )

                HStack(spacing: 0) {
                    OnboardingRankMetric(
                        symbol: "checkmark.seal",
                        value: "145",
                        label: "Settled calls"
                    )
                    Divider().overlay(BSmartColor.line)
                    OnboardingRankMetric(
                        symbol: "chart.line.uptrend.xyaxis",
                        value: "2",
                        label: "Market baselines"
                    )
                    Divider().overlay(BSmartColor.line)
                    OnboardingRankMetric(
                        symbol: "clock.arrow.circlepath",
                        value: "Live",
                        label: "Time weighted"
                    )
                }
                .padding(.vertical, BSmartSpacing.small)
                .background(BSmartColor.recessed)
                .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                        .stroke(BSmartColor.line, lineWidth: 0.5)
                }
            }
        }
    }

    private var productPage: some View {
        OnboardingPageFrame(
            eyebrow: "FROM SIGNALS TO JUDGMENT",
            title: "See bSmart in action",
            lead: nil
        ) {
            GeometryReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        OnboardingJudgmentExample(
                            symbol: "person.3.sequence.fill",
                            color: BSmartColor.brand,
                            title: "Smart Consensus",
                            ticker: "NVDA",
                            headline: "4 top accounts are converging on the reasoning around NVDA",
                            detail: "Independent judgments · one theme",
                            accounts: Array(accountCandidates.prefix(3))
                        )
                        .onboardingFeatureSurface()

                        Spacer(minLength: BSmartSpacing.xLarge)

                        OnboardingJudgmentExample(
                            symbol: "sparkles",
                            color: BSmartColor.gold,
                            title: "Smart Alpha",
                            ticker: "MSTR",
                            headline: "A Top 2% account introduces a new MSTR thesis",
                            detail: "A high-ranked source before consensus",
                            accounts: alphaAccount.map { [$0] } ?? []
                        )
                        .onboardingFeatureSurface()

                        Spacer(minLength: BSmartSpacing.xLarge)

                        OnboardingCompactExample(
                            symbol: "bell.badge.fill",
                            color: BSmartColor.sky,
                            title: "Tracking",
                            headline: "A new NVDA thesis from %@".bSmartLocalized(featuredAccountName),
                            detail: "Follow the account once; its next qualified change comes to you."
                        )
                        .onboardingFeatureSurface()

                        Spacer(minLength: BSmartSpacing.xLarge)

                        OnboardingCompactExample(
                            imageName: "SmartMoneyBorderCollie",
                            color: BSmartColor.pulse,
                            title: "Mr Collie",
                            headline: "What changed in NVDA this week?",
                            detail: "Compare ranked judgments and open their evidence."
                        )
                        .onboardingFeatureSurface()
                    }
                    .frame(
                        minHeight: max(0, proxy.size.height - BSmartSpacing.small),
                        alignment: .top
                    )
                    .padding(.bottom, BSmartSpacing.small)
                }
            }
        }
    }

    private var setupPage: some View {
        OnboardingPageFrame(
            eyebrow: "BUILD YOUR JUDGMENT NETWORK",
            title: "Connect your portfolio, then choose who to track",
            lead: nil
        ) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: BSmartSpacing.xLarge) {
                    VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
                        setupSectionTitle(
                            "Connect a brokerage",
                            detail: model.linkedBrokerageAccounts.isEmpty ? nil : "Linked"
                        )

                        OnboardingBrokerageChoice(
                            providers: BrokerageProvider.allCases,
                            linkedCount: model.linkedBrokerageAccounts.count
                        ) {
                            isShowingBrokerageConnections = true
                        }
                    }

                    VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
                        setupSectionTitle("Smart Accounts", detail: followedAccountCount == 0 ? nil : "\(followedAccountCount)")

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: BSmartSpacing.medium) {
                                ForEach(Array(accountCandidates.prefix(6))) { account in
                                    OnboardingCompactAccountChoice(
                                        account: account,
                                        isFollowing: model.isFollowingSmartAccount(account.id)
                                    ) {
                                        model.toggleSmartAccountFollow(account.id)
                                    }
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
                        setupSectionTitle("Smart Money", detail: followedMoneyCount == 0 ? nil : "\(followedMoneyCount)")

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: BSmartSpacing.medium) {
                                ForEach(Array(moneyCandidates.prefix(6))) { money in
                                    OnboardingCompactMoneyChoice(
                                        signal: money,
                                        isFollowing: model.isFollowingSmartMoney(money.id)
                                    ) {
                                        model.toggleSmartMoneyFollow(money.id)
                                    }
                                }
                            }
                        }

                        if accountCandidates.isEmpty && moneyCandidates.isEmpty {
                            Label("Intelligence accounts are still loading".bSmartLocalized, systemImage: "arrow.triangle.2.circlepath")
                                .font(.caption)
                                .foregroundStyle(BSmartColor.secondaryText)
                                .frame(maxWidth: .infinity, minHeight: 70)
                                .background(BSmartColor.surface)
                                .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
                        }
                    }
                }
                .padding(.bottom, BSmartSpacing.medium)
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: BSmartSpacing.large) {
            HStack(spacing: 6) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? BSmartColor.brand : BSmartColor.strongLine)
                        .frame(width: index == page ? 20 : 6, height: 6)
                        .animation(BSmartMotion.standard, value: page)
                }
            }

            Button(action: continueFlow) {
                HStack {
                    Text(primaryButtonTitle.bSmartLocalized)
                    Spacer()
                    Image(systemName: page == pageCount - 1 ? "checkmark" : "arrow.right")
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(BSmartColor.pulseInk)
                .padding(.horizontal, BSmartSpacing.large)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(BSmartColor.brand)
                .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))
            }
            .disabled(page == pageCount - 1 && !canFinish)
            .opacity(page == pageCount - 1 && !canFinish ? 0.42 : 1)
            .accessibilityIdentifier(page == pageCount - 1 ? "onboarding.finish" : "onboarding.continue")
        }
        .padding(.top, BSmartSpacing.small)
    }

    private var primaryButtonTitle: String {
        switch page {
        case 0: "See what bSmart finds"
        case 1: "Build my network"
        default: canFinish ? "Open bSmart" : "Connect and track to continue"
        }
    }

    private var canFinish: Bool {
        !model.linkedBrokerageAccounts.isEmpty && followedCount > 0
    }

    private var followedCount: Int {
        model.followedSmartAccountIDs.count + model.followedSmartMoneyIDs.count
    }

    private var followedAccountCount: Int {
        model.followedSmartAccountIDs.count
    }

    private var followedMoneyCount: Int {
        model.followedSmartMoneyIDs.count
    }

    private var accountCandidates: [SmartAccountProfile] {
        model.smartAccounts
            .filter { $0.avatarURL != nil }
            .sorted { lhs, rhs in
                if lhs.resolvedPlatformPercentile != rhs.resolvedPlatformPercentile {
                    return lhs.resolvedPlatformPercentile < rhs.resolvedPlatformPercentile
                }
                return lhs.score > rhs.score
            }
    }

    private var moneyCandidates: [SmartMoneySignal] {
        model.smartMoney.sorted { lhs, rhs in
            if let lhsRank = lhs.rank, let rhsRank = rhs.rank, lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return lhs.score > rhs.score
        }
    }

    private var alphaAccount: SmartAccountProfile? {
        accountCandidates.dropFirst(min(2, accountCandidates.count)).first ?? accountCandidates.first
    }

    private var featuredAccountName: String {
        guard let account = accountCandidates.first else { return "a Top 5% account".bSmartLocalized }
        return account.name.isEmpty ? account.handle : account.name
    }

    private func setupSectionTitle(_ title: String, detail: String?) -> some View {
        HStack {
            Text(title.bSmartLocalized)
                .font(.caption.weight(.bold))
                .foregroundStyle(BSmartColor.primaryText)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.caption2.weight(.black))
                    .foregroundStyle(BSmartColor.brand)
                    .monospacedDigit()
            }
        }
    }

    private func continueFlow() {
        UISelectionFeedbackGenerator().selectionChanged()
        if page < pageCount - 1 {
            withAnimation(BSmartMotion.standard) { page += 1 }
        } else if canFinish {
            _ = model.completePortfolioSetup()
        }
    }
}

private struct OnboardingPageFrame<Content: View>: View {
    let eyebrow: String
    let title: String
    let lead: String?
    let content: Content

    init(
        eyebrow: String,
        title: String,
        lead: String?,
        @ViewBuilder content: () -> Content
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.lead = lead
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            VStack(alignment: .leading, spacing: BSmartSpacing.small) {
                Text(eyebrow.bSmartLocalized)
                    .font(.system(size: 10, weight: .black))
                    .tracking(1)
                    .foregroundStyle(BSmartColor.brand)

                Text(title.bSmartLocalized)
                    .font(.system(size: 29, weight: .black, design: .rounded))
                    .foregroundStyle(BSmartColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if let lead {
                    Text(lead.bSmartLocalized)
                        .font(.subheadline)
                        .foregroundStyle(BSmartColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.top, BSmartSpacing.medium)
        .padding(.bottom, BSmartSpacing.small)
    }
}

private extension View {
    func onboardingFeatureSurface() -> some View {
        padding(.horizontal, BSmartSpacing.medium)
            .background(BSmartColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                    .stroke(BSmartColor.line, lineWidth: 0.5)
            }
    }
}

private struct OnboardingPriceEvidenceChart: View {
    let accounts: [SmartAccountProfile]
    let money: SmartMoneySignal?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: BSmartSpacing.small) {
                BSmartAssetMark(ticker: "NVDA", size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("NVDA")
                        .font(.headline.weight(.black))
                    Text("$182.14")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(BSmartColor.secondaryText)
                }
                Spacer()
                Text("+3.8%")
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(BSmartColor.brand)
                    .monospacedDigit()
            }
            .padding(.horizontal, BSmartSpacing.medium)
            .padding(.top, BSmartSpacing.medium)

            GeometryReader { proxy in
                ZStack {
                    OnboardingPriceLine()
                        .stroke(BSmartColor.brand, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                    if let first = accounts.first {
                        marker(
                            avatarURL: first.avatarURL,
                            name: first.name.isEmpty ? first.handle : first.name,
                            rank: percentileLabel(first.resolvedPlatformPercentile),
                            color: BSmartColor.brand
                        )
                        .position(x: proxy.size.width * 0.23, y: proxy.size.height * 0.61)
                    }

                    if accounts.count > 1 {
                        let second = accounts[1]
                        marker(
                            avatarURL: second.avatarURL,
                            name: second.name.isEmpty ? second.handle : second.name,
                            rank: percentileLabel(second.resolvedPlatformPercentile),
                            color: BSmartColor.brand
                        )
                        .position(x: proxy.size.width * 0.57, y: proxy.size.height * 0.42)
                    }

                    if let money {
                        VStack(spacing: 2) {
                            BSmartSmartMoneyAvatar(identity: money.publicIdentity, size: 42)
                            Text(money.rank.map { "#\($0)" } ?? "Smart")
                                .font(.system(size: 8, weight: .black))
                                .foregroundStyle(BSmartColor.sky)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(BSmartColor.surface)
                                .clipShape(Capsule())
                        }
                        .position(x: proxy.size.width * 0.82, y: proxy.size.height * 0.26)
                    }
                }
                .background {
                    OnboardingChartGrid()
                        .stroke(BSmartColor.line.opacity(0.72), lineWidth: 0.5)
                }
            }
            .frame(height: 210)
            .padding(.horizontal, BSmartSpacing.medium)

            HStack {
                Label("Smart Account".bSmartLocalized, systemImage: "person.crop.circle")
                Spacer()
                Label("Smart Money".bSmartLocalized, systemImage: "wallet.bifold")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(BSmartColor.tertiaryText)
            .padding(.horizontal, BSmartSpacing.medium)
            .padding(.bottom, BSmartSpacing.medium)
        }
        .background(BSmartColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                .stroke(BSmartColor.line, lineWidth: 0.5)
        }
    }

    private func marker(
        avatarURL: URL?,
        name: String,
        rank: String,
        color: Color
    ) -> some View {
        VStack(spacing: 2) {
            BSmartAvatar(url: avatarURL, name: name, size: 42, fallbackColor: color)
                .overlay { Circle().stroke(color, lineWidth: 2) }
            Text(rank)
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(color)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(BSmartColor.surface)
                .clipShape(Capsule())
        }
    }

    private func percentileLabel(_ percentile: Double) -> String {
        let normalized = percentile <= 1 ? percentile * 100 : percentile
        return "Top \(max(1, Int(normalized.rounded())))%"
    }
}

private struct OnboardingPriceLine: Shape {
    func path(in rect: CGRect) -> Path {
        let points = [
            CGPoint(x: 0.02, y: 0.82), CGPoint(x: 0.10, y: 0.75),
            CGPoint(x: 0.18, y: 0.79), CGPoint(x: 0.25, y: 0.58),
            CGPoint(x: 0.34, y: 0.66), CGPoint(x: 0.43, y: 0.49),
            CGPoint(x: 0.52, y: 0.57), CGPoint(x: 0.61, y: 0.38),
            CGPoint(x: 0.69, y: 0.46), CGPoint(x: 0.77, y: 0.23),
            CGPoint(x: 0.85, y: 0.30), CGPoint(x: 0.98, y: 0.11),
        ]

        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: first.x * rect.width, y: first.y * rect.height))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: point.x * rect.width, y: point.y * rect.height))
        }
        return path
    }
}

private struct OnboardingChartGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for fraction in [0.25, 0.5, 0.75] {
            path.move(to: CGPoint(x: 0, y: rect.height * fraction))
            path.addLine(to: CGPoint(x: rect.width, y: rect.height * fraction))
        }
        return path
    }
}

private struct OnboardingRankMetric: View {
    let symbol: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(BSmartColor.brand)
            Text(value.bSmartLocalized)
                .font(.caption.weight(.black))
                .monospacedDigit()
            Text(label.bSmartLocalized)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(BSmartColor.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
    }
}

private struct OnboardingJudgmentExample: View {
    let symbol: String
    let color: Color
    let title: String
    let ticker: String
    let headline: String
    let detail: String
    let accounts: [SmartAccountProfile]

    var body: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.small) {
            HStack(spacing: BSmartSpacing.small) {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(color)
                    .frame(width: 34, height: 34)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title.bSmartLocalized)
                        .font(.subheadline.weight(.bold))
                    Text(title == "Smart Consensus" ? "SMART CONSENSUS" : "SMART ALPHA")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(BSmartColor.tertiaryText)
                }

                Spacer()
                BSmartAssetMark(ticker: ticker, size: 32)
            }

            Text(headline.bSmartLocalized)
                .font(.headline.weight(.black))
                .foregroundStyle(BSmartColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: BSmartSpacing.small) {
                OnboardingAvatarStack(accounts: accounts, color: color)
                Text(detail.bSmartLocalized)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(BSmartColor.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, BSmartSpacing.large)
    }
}

private struct OnboardingAvatarStack: View {
    let accounts: [SmartAccountProfile]
    let color: Color

    var body: some View {
        HStack(spacing: -7) {
            if accounts.isEmpty {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title2)
                    .foregroundStyle(BSmartColor.tertiaryText)
            } else {
                ForEach(Array(accounts.prefix(3))) { account in
                    BSmartAvatar(
                        url: account.avatarURL,
                        name: account.name.isEmpty ? account.handle : account.name,
                        size: 28,
                        fallbackColor: color
                    )
                    .overlay { Circle().stroke(BSmartColor.surface, lineWidth: 2) }
                }
            }
        }
    }
}

private struct OnboardingCompactExample: View {
    var symbol: String?
    var imageName: String?
    let color: Color
    let title: String
    let headline: String
    let detail: String

    var body: some View {
        HStack(spacing: BSmartSpacing.medium) {
            Group {
                if let imageName {
                    Image(imageName)
                        .resizable()
                        .scaledToFill()
                } else if let symbol {
                    Image(systemName: symbol)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(color)
                }
            }
            .frame(width: 38, height: 38)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title.bSmartLocalized.uppercased())
                    .font(.system(size: 9, weight: .black))
                    .tracking(0.7)
                    .foregroundStyle(color)
                Text(headline)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BSmartColor.primaryText)
                    .lineLimit(2)
                Text(detail.bSmartLocalized)
                    .font(.caption2)
                    .foregroundStyle(BSmartColor.secondaryText)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, BSmartSpacing.medium)
    }
}

private struct OnboardingBrokerageChoice: View {
    let providers: [BrokerageProvider]
    let linkedCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: BSmartSpacing.large) {
                HStack {
                    HStack(spacing: -5) {
                        ForEach(providers) { provider in
                            BrokerageProviderBadge(provider: provider, size: 38)
                                .overlay {
                                    RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                                        .stroke(BSmartColor.surface, lineWidth: 2)
                                }
                        }
                    }
                    Spacer()
                    Label("Read-only access".bSmartLocalized, systemImage: "lock.shield.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BSmartColor.secondaryText)
                }

                HStack(spacing: BSmartSpacing.medium) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(linkedCount > 0 ? "Brokerage linked".bSmartLocalized : "Bring in your real portfolio".bSmartLocalized)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(BSmartColor.primaryText)
                        Text("Robinhood · IBKR · Binance · Coinbase")
                            .font(.caption2)
                            .foregroundStyle(BSmartColor.secondaryText)
                    }
                    Spacer()
                    Image(systemName: linkedCount > 0 ? "checkmark.circle.fill" : "arrow.right.circle.fill")
                        .font(.title2)
                        .foregroundStyle(BSmartColor.brand)
                }
            }
            .padding(BSmartSpacing.large)
            .background(linkedCount > 0 ? BSmartColor.brand.opacity(0.08) : BSmartColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                    .stroke(linkedCount > 0 ? BSmartColor.brand : BSmartColor.line, lineWidth: linkedCount > 0 ? 1 : 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding.connect-brokerage")
    }
}

private struct OnboardingCompactAccountChoice: View {
    let account: SmartAccountProfile
    let isFollowing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: BSmartSpacing.small) {
                HStack {
                BSmartAvatar(
                    url: account.avatarURL,
                    name: account.name.isEmpty ? account.handle : account.name,
                        size: 42,
                    fallbackColor: BSmartColor.brand
                )
                Spacer()
                    Image(systemName: isFollowing ? "checkmark.circle.fill" : "plus.circle")
                        .foregroundStyle(isFollowing ? BSmartColor.brand : BSmartColor.tertiaryText)
                }

                Text(account.name.isEmpty ? account.handle : account.name)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BSmartColor.primaryText)
                    .lineLimit(1)
                Text(percentileLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(BSmartColor.brand)
            }
            .padding(BSmartSpacing.medium)
            .frame(width: 152, height: 116, alignment: .leading)
            .background(isFollowing ? BSmartColor.brand.opacity(0.08) : BSmartColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                    .stroke(isFollowing ? BSmartColor.brand : BSmartColor.line, lineWidth: isFollowing ? 1 : 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding.follow-account.\(account.id)")
    }

    private var percentileLabel: String {
        let value = account.resolvedPlatformPercentile <= 1
            ? account.resolvedPlatformPercentile * 100
            : account.resolvedPlatformPercentile
        return "Top \(max(1, Int(value.rounded())))%"
    }

}

private struct OnboardingCompactMoneyChoice: View {
    let signal: SmartMoneySignal
    let isFollowing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: BSmartSpacing.small) {
                HStack {
                    BSmartSmartMoneyAvatar(identity: signal.publicIdentity, size: 42)
                Spacer()
                    Image(systemName: isFollowing ? "checkmark.circle.fill" : "plus.circle")
                        .foregroundStyle(isFollowing ? BSmartColor.brand : BSmartColor.tertiaryText)
                }

                Text(signal.publicIdentity.displayName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BSmartColor.primaryText)
                    .lineLimit(1)
                Text(rankLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(BSmartColor.sky)
            }
            .padding(BSmartSpacing.medium)
            .frame(width: 152, height: 116, alignment: .leading)
            .background(isFollowing ? BSmartColor.brand.opacity(0.08) : BSmartColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                    .stroke(isFollowing ? BSmartColor.brand : BSmartColor.line, lineWidth: isFollowing ? 1 : 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding.follow-money.\(signal.id)")
    }

    private var rankLabel: String {
        signal.rank.map { "#\($0)" } ?? signal.resolvedTier
    }
}
