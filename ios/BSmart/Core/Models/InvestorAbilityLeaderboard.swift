import Foundation

enum AbilityActorKind: String, Codable, CaseIterable {
    case platform, politician, celebrity, insider, institution

    var title: String {
        switch self {
        case .platform: "Platform accounts"
        case .politician: "Politicians"
        case .celebrity: "Celebrities"
        case .insider: "Company insiders"
        case .institution: "Institutions"
        }
    }
}

enum AbilityScoreStatus: String, Codable {
    case scored, insufficientHistory = "insufficient_history", unverifiedSource = "unverified_source"
    case unauditedBacktest = "unaudited_backtest", incompletePrices = "incomplete_prices"
    case noObservableTrade = "no_observable_trade"

    var title: String {
        switch self {
        case .scored: "Scored"
        case .insufficientHistory: "Insufficient history"
        case .unverifiedSource: "Source not verified"
        case .unauditedBacktest: "Backtest not audited"
        case .incompletePrices: "Incomplete prices"
        case .noObservableTrade: "No observable trade"
        }
    }
}

struct InvestorAbilityItem: Decodable, Identifiable {
    let actorKind: AbilityActorKind
    let actorId: String
    let displayName: String
    let platform: String?
    let avatarURL: URL?
    let status: AbilityScoreStatus
    let score: Double?
    let observedCalendarDays: Int
    let independentDecisionDays: Int
    let pricedCoverage: Double
    var rank: Int?
    var winRate: Double? = nil
    var winRateMethod: String? = nil
    var winRateObservations: Int? = nil
    var winRateWins: Int? = nil
    var winRateLosses: Int? = nil
    var followReturn: Double? = nil
    var followReturnMethod: String? = nil

    var id: String { actorKind.rawValue + ":" + actorId }
    var scoreLabel: String {
        guard let score else { return "Pending score".bSmartLocalized }
        return score.formatted(.number.sign(strategy: .always()).precision(.fractionLength(1)))
    }
}

struct InvestorAbilityLeaderboard: Decodable {
    enum Status: String, Decodable { case published, unpublished, mock, research }
    let status: Status
    let version: String
    let revision: Int?
    let asOf: Date?
    let scoreUnit: String
    let items: [InvestorAbilityItem]

    var isMock: Bool { status == .mock }
    var isResearch: Bool { status == .research }

    static let bundledResearch: Self? = {
        guard let url = Bundle.main.url(forResource: "ability-research-snapshot", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let snapshot = try? BSmartJSONCoding.makeDecoder().decode(Self.self, from: data) else { return nil }
        return try? snapshot.validate()
    }()

    static func researchMetric(kind: AbilityActorKind, id: String) -> InvestorAbilityItem? {
        bundledResearch?.items.first { $0.actorKind == kind && $0.actorId == id }
    }

    func replacingSubjectResearch(with subjects: [TodaySubjectProfile]) -> Self {
        guard isResearch else { return self }
        var lastScore: Double?
        var lastRank = 0
        let platformItems = items.filter { $0.actorKind == .platform }
        let scoredPlatforms = platformItems.filter { $0.score != nil }.enumerated().map { index, source in
            var item = source
            if item.score != lastScore { lastRank = index + 1 }
            item.rank = lastRank
            lastScore = item.score
            return item
        }
        let subjectItems = subjects.sorted { $0.id < $1.id }.map { subject in
            let kind: AbilityActorKind = switch subject.kind {
            case .politician: .politician
            case .celebrity: .celebrity
            case .institution: .institution
            }
            let research = subject.research
            return InvestorAbilityItem(
                actorKind: kind, actorId: subject.id, displayName: subject.name,
                platform: nil, avatarURL: subject.avatarURL,
                status: research == nil ? .noObservableTrade : .unauditedBacktest,
                score: nil, observedCalendarDays: 0, independentDecisionDays: 0,
                pricedCoverage: research.flatMap { $0.candidatePositions > 0
                    ? Double($0.pricedPositions) / Double($0.candidatePositions) : nil } ?? 0,
                rank: nil,
                winRate: research?.winRateFromDecidedOutcomes,
                winRateMethod: research?.winRateFromDecidedOutcomes == nil ? nil : "latest_directional_price",
                winRateObservations: research.map { $0.directionalWins + $0.directionalLosses },
                winRateWins: research?.directionalWins,
                winRateLosses: research?.directionalLosses,
                followReturn: research?.meanOpenReturn,
                followReturnMethod: research?.meanOpenReturn == nil ? nil : "open_position_equal_weight_absolute"
            )
        }
        return Self(status: status, version: version, revision: revision, asOf: asOf,
                    scoreUnit: scoreUnit, items: scoredPlatforms
                        + platformItems.filter { $0.score == nil } + subjectItems)
    }

    func balancedMock() -> Self {
        let kinds: [AbilityActorKind] = [.platform, .politician, .celebrity, .institution, .insider]
        func stableKey(_ item: InvestorAbilityItem) -> UInt64 {
            item.id.utf8.reduce(UInt64(14_695_981_039_346_656_037)) {
                ($0 ^ UInt64($1)) &* 1_099_511_628_211
            }
        }
        let queues = Dictionary(grouping: items, by: \.actorKind).mapValues { candidates in
            candidates.sorted { lhs, rhs in
                if let left = lhs.score, let right = rhs.score, left != right { return left > right }
                if (lhs.score != nil) != (rhs.score != nil) { return lhs.score != nil }
                let left = stableKey(lhs), right = stableKey(rhs)
                return left == right ? lhs.id < rhs.id : left > right
            }
        }
        var positions: [AbilityActorKind: Int] = [:]
        var ordered: [InvestorAbilityItem] = []
        ordered.reserveCapacity(items.count)
        while ordered.count < items.count {
            for kind in kinds {
                guard let candidates = queues[kind] else { continue }
                let index = positions[kind, default: 0]
                guard index < candidates.count else { continue }
                ordered.append(candidates[index])
                positions[kind] = index + 1
            }
        }
        var previousScore: Double?
        var previousRank = 0
        let anchor = items.compactMap(\.score).max() ?? 0
        let ranked = ordered.enumerated().map { index, source in
            let score = ((anchor - 4 * log2(Double(index + 1))) * 10).rounded() / 10
            let rank = score == previousScore ? previousRank : index + 1
            previousScore = score
            previousRank = rank
            return InvestorAbilityItem(
                actorKind: source.actorKind, actorId: source.actorId, displayName: source.displayName,
                platform: source.platform, avatarURL: source.avatarURL, status: .scored,
                score: score, observedCalendarDays: source.observedCalendarDays,
                independentDecisionDays: source.independentDecisionDays,
                pricedCoverage: source.pricedCoverage, rank: rank,
                winRate: source.winRate, winRateMethod: source.winRateMethod,
                winRateObservations: source.winRateObservations, winRateWins: source.winRateWins,
                winRateLosses: source.winRateLosses, followReturn: source.followReturn,
                followReturnMethod: source.followReturnMethod
            )
        }
        return Self(status: .mock, version: "mock-v1", revision: nil, asOf: nil,
                    scoreUnit: "mock_points", items: ranked)
    }

    func includingMockUser(id: String, name: String, avatarURL: URL?) -> Self {
        let actorID = "bsmart:\(id)"
        guard !items.contains(where: { $0.actorKind == .platform && $0.actorId == actorID }) else { return self }
        let hash = actorID.utf8.reduce(UInt64(14_695_981_039_346_656_037)) {
            ($0 ^ UInt64($1)) &* 1_099_511_628_211
        }
        let platformScores = items.filter { $0.actorKind == .platform }.compactMap(\.score).sorted(by: >)
        let seed = platformScores.isEmpty ? 0 : platformScores[Int(hash % UInt64(platformScores.count))]
        let user = InvestorAbilityItem(
            actorKind: .platform, actorId: actorID, displayName: name,
            platform: "bsmart", avatarURL: avatarURL, status: .scored, score: seed,
            observedCalendarDays: 0, independentDecisionDays: 0, pricedCoverage: 0, rank: nil
        )
        return Self(status: status, version: version, revision: revision, asOf: asOf,
                    scoreUnit: scoreUnit, items: items + [user])
    }

    static func mock(accounts: [SmartAccountProfile], subjects: [TodaySubjectProfile]) -> Self {
        struct Candidate {
            let kind: AbilityActorKind
            let id: String
            let name: String
            let platform: String?
            let avatarURL: URL?
            let score: Double
        }

        func mockScore(kind: AbilityActorKind, id: String) -> Double {
            let key = "\(kind.rawValue):\(id)"
            let hash = key.utf8.reduce(UInt64(14_695_981_039_346_656_037)) {
                ($0 ^ UInt64($1)) &* 1_099_511_628_211
            }
            return Double(Int(hash % 441) - 100) / 10
        }

        let platformCandidates = accounts.map { account in
            Candidate(kind: .platform, id: account.id, name: account.name, platform: account.platform,
                      avatarURL: account.avatarURL, score: mockScore(kind: .platform, id: account.id))
        }
        let subjectCandidates = subjects.map { subject in
            let kind: AbilityActorKind = switch subject.kind {
            case .politician: .politician
            case .celebrity: .celebrity
            case .institution: .institution
            }
            return Candidate(kind: kind, id: subject.id, name: subject.name, platform: nil,
                             avatarURL: subject.avatarURL, score: mockScore(kind: kind, id: subject.id))
        }
        var seen = Set<String>()
        let ranked = (platformCandidates + subjectCandidates)
            .filter { seen.insert("\($0.kind.rawValue):\($0.id)").inserted }
            .sorted { $0.score == $1.score ? "\($0.kind.rawValue):\($0.id)" < "\($1.kind.rawValue):\($1.id)" : $0.score > $1.score }
        var lastScore: Double?
        var lastRank = 0
        let items = ranked.enumerated().map { index, candidate in
            let rank = candidate.score == lastScore ? lastRank : index + 1
            lastScore = candidate.score
            lastRank = rank
            return InvestorAbilityItem(actorKind: candidate.kind, actorId: candidate.id,
                                       displayName: candidate.name, platform: candidate.platform,
                                       avatarURL: candidate.avatarURL, status: .scored, score: candidate.score,
                                       observedCalendarDays: 0, independentDecisionDays: 0,
                                       pricedCoverage: 0, rank: rank)
        }
        return Self(status: .mock, version: "mock-v1", revision: nil, asOf: nil,
                    scoreUnit: "mock_points", items: items)
    }

    func validate() throws -> Self {
        let validContract = switch status {
        case .mock: version == "mock-v1" && scoreUnit == "mock_points" && revision == nil && asOf == nil
        case .research: version == "follow-ability-research-v1" && scoreUnit == "research_candidate_pp"
        case .published, .unpublished: version == "follow-ability-v1" && scoreUnit == "annualized_adjusted_pp"
        }
        guard validContract, items.count <= 10_000, Set(items.map(\.id)).count == items.count else {
            throw BSmartAPIError.invalidResponse
        }
        if status == .unpublished {
            guard revision == nil, asOf == nil, items.isEmpty else { throw BSmartAPIError.invalidResponse }
            return self
        }
        if status == .published || status == .research {
            guard let revision, revision > 0, asOf != nil else { throw BSmartAPIError.invalidResponse }
        }
        var previousScore: Double?
        var previousRank = 0
        var reachedPending = false
        for (index, item) in items.enumerated() {
            guard !item.actorId.isEmpty, !item.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  item.observedCalendarDays >= 0, item.independentDecisionDays >= 0,
                  item.independentDecisionDays <= item.observedCalendarDays,
                  item.pricedCoverage.isFinite, (0...1).contains(item.pricedCoverage) else {
                throw BSmartAPIError.invalidResponse
            }
            if let winRate = item.winRate {
                guard winRate.isFinite, (0...1).contains(winRate),
                      let count = item.winRateObservations, count > 0,
                      let wins = item.winRateWins, let losses = item.winRateLosses,
                      wins >= 0, losses >= 0, wins + losses <= count,
                      item.winRateMethod == "closed_trade_30d" || item.winRateMethod == "latest_directional_price" else {
                    throw BSmartAPIError.invalidResponse
                }
            }
            if let followReturn = item.followReturn, !followReturn.isFinite {
                throw BSmartAPIError.invalidResponse
            }
            if status == .research, item.followReturn != nil,
               item.followReturnMethod != "long_only_30d_portfolio"
                && item.followReturnMethod != "directional_30d_proxy"
                && item.followReturnMethod != "open_position_equal_weight_absolute" {
                throw BSmartAPIError.invalidResponse
            }
            if let score = item.score {
                guard !reachedPending, item.status == .scored, score.isFinite,
                      previousScore == nil || score <= previousScore! else { throw BSmartAPIError.invalidResponse }
                let expectedRank = score == previousScore ? previousRank : index + 1
                guard item.rank == expectedRank else { throw BSmartAPIError.invalidResponse }
                previousRank = expectedRank; previousScore = score
            } else {
                guard status != .mock else { throw BSmartAPIError.invalidResponse }
                reachedPending = true
                guard item.status != .scored, item.rank == nil else { throw BSmartAPIError.invalidResponse }
            }
        }
        return self
    }
}
