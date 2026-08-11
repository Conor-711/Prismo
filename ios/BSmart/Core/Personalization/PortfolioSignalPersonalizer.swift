import Foundation

enum PortfolioRelationship: String, Hashable {
    case position
    case watchlist
    case untracked

    var label: String {
        switch self {
        case .position: "Your position"
        case .watchlist: "Your watchlist"
        case .untracked: "Not tracked"
        }
    }
}

enum PersonalizedAttentionLevel: Int, Hashable, Comparable {
    case monitor = 1
    case review = 2
    case priority = 3

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .priority: "Priority"
        case .review: "Review"
        case .monitor: "Monitor"
        }
    }
}

struct PortfolioSignalPersonalization: Hashable {
    let signalID: UUID
    let relationship: PortfolioRelationship
    let attention: PersonalizedAttentionLevel
    let relevanceScore: Int
    let positionWeight: Double?
    let costDistancePercent: Double?
    let contextSummary: String
    let impactText: String
    let attentionReason: String
}

struct PersonalizedPortfolioSignal: Identifiable, Hashable {
    var id: UUID { signal.id }
    let signal: PortfolioSignal
    let personalization: PortfolioSignalPersonalization
}

enum PortfolioSignalPersonalizer {
    static func personalize(
        signal: PortfolioSignal,
        position: PortfolioPosition?,
        resolvedWeight: Double
    ) -> PortfolioSignalPersonalization {
        let relationship = relationship(for: position)
        let weight = relationship == .position && resolvedWeight > 0 ? min(resolvedWeight, 1) : nil
        let costDistance = costDistancePercent(for: position)
        let score = relevanceScore(
            signal: signal,
            relationship: relationship,
            weight: weight,
            costDistance: costDistance
        )
        let attention: PersonalizedAttentionLevel = if score >= 80 {
            .priority
        } else if score >= 55 {
            .review
        } else {
            .monitor
        }

        return PortfolioSignalPersonalization(
            signalID: signal.id,
            relationship: relationship,
            attention: attention,
            relevanceScore: score,
            positionWeight: weight,
            costDistancePercent: costDistance,
            contextSummary: contextSummary(
                relationship: relationship,
                weight: weight,
                costDistance: costDistance
            ),
            impactText: impactText(
                signal: signal,
                relationship: relationship,
                weight: weight,
                costDistance: costDistance,
                hasCostBasis: hasCostBasis(position)
            ),
            attentionReason: attentionReason(
                signal: signal,
                attention: attention,
                relationship: relationship,
                weight: weight,
                costDistance: costDistance
            )
        )
    }

    private static func relationship(for position: PortfolioPosition?) -> PortfolioRelationship {
        switch position?.resolvedKind {
        case .position: .position
        case .watchlist: .watchlist
        case nil: .untracked
        }
    }

    private static func hasCostBasis(_ position: PortfolioPosition?) -> Bool {
        guard let position, position.resolvedKind == .position else { return false }
        return position.averageCost > 0
    }

    private static func costDistancePercent(for position: PortfolioPosition?) -> Double? {
        guard
            let position,
            position.resolvedKind == .position,
            position.averageCost > 0,
            position.currentPrice > 0
        else { return nil }
        return (position.currentPrice - position.averageCost) / position.averageCost
    }

    private static func relevanceScore(
        signal: PortfolioSignal,
        relationship: PortfolioRelationship,
        weight: Double?,
        costDistance: Double?
    ) -> Int {
        var score = switch signal.priority {
        case .critical: 60
        case .important: 45
        case .notable: 30
        }

        let kindBonus = switch signal.kind {
        case .divergence: 16
        case .confirmation: 8
        case .smartAccountShift: 8
        case .smartAccountConsensus, .smartMoneyMovement: 7
        case .accountLeads, .moneyLeads: 5
        case .smartAccountNewView: 4
        }
        score += kindBonus

        switch relationship {
        case .position:
            score += 12
            if let weight {
                if weight >= 0.25 {
                    score += 14
                } else if weight >= 0.10 {
                    score += 8
                } else {
                    score += 4
                }
            }
        case .watchlist:
            score += 4
        case .untracked:
            break
        }

        if let costDistance, relationship == .position {
            switch signal.direction {
            case .bearish, .mixed:
                if costDistance <= -0.05 {
                    score += 10
                } else if costDistance < 0.05 {
                    score += 6
                } else {
                    score += 3
                }
            case .bullish:
                if costDistance <= -0.05 { score += 5 }
                if costDistance >= 0.20, (weight ?? 0) >= 0.20 { score += 4 }
            case .neutral:
                break
            }
        }

        if signal.resolvedDataStatus == .delayed { score -= 8 }
        if signal.smartMoneyCoverage == .unavailable { score -= 2 }
        return min(max(score, 0), 100)
    }

    private static func contextSummary(
        relationship: PortfolioRelationship,
        weight: Double?,
        costDistance: Double?
    ) -> String {
        switch relationship {
        case .watchlist:
            return "Watchlist · no capital exposed"
        case .untracked:
            return "Outside your portfolio"
        case .position:
            var parts = [weight.map(percentText) ?? "Held position"]
            if let costDistance {
                parts.append(costDistanceText(costDistance))
            } else {
                parts.append("cost not entered")
            }
            return parts.joined(separator: " · ")
        }
    }

    private static func impactText(
        signal: PortfolioSignal,
        relationship: PortfolioRelationship,
        weight: Double?,
        costDistance: Double?,
        hasCostBasis: Bool
    ) -> String {
        switch relationship {
        case .watchlist:
            return "You are watching \(signal.ticker), but no portfolio capital is exposed. Use this change to decide whether the ticker still belongs on your research list."
        case .untracked:
            return "\(signal.ticker) is outside your portfolio and watchlist. Compare this evidence with the exposures you already hold before adding it to your research list."
        case .position:
            let exposure = weight.map { "\(percentText($0)) of your portfolio" } ?? "a held position"
            let opening: String
            if let costDistance {
                opening = "\(signal.ticker) is \(exposure) and trades \(costDistanceText(costDistance))."
            } else if hasCostBasis {
                opening = "\(signal.ticker) is \(exposure), but a current price is unavailable for comparison with your cost basis."
            } else {
                opening = "\(signal.ticker) is \(exposure). Add a cost basis to place this change against your entry."
            }

            return "\(opening) \(relationshipInterpretation(signal: signal, weight: weight, costDistance: costDistance))"
        }
    }

    private static func relationshipInterpretation(
        signal: PortfolioSignal,
        weight: Double?,
        costDistance: Double?
    ) -> String {
        switch signal.kind {
        case .divergence:
            if let costDistance, costDistance < 0 {
                return "Qualified views and public capital disagree while the position is below cost, so the thesis and downside limit deserve closer review."
            }
            return "Qualified views and public capital disagree, so follow-through and the thesis invalidation level matter more than either signal alone."
        case .confirmation:
            if (weight ?? 0) >= 0.25 {
                return "Independent evidence confirms the current direction, but the concentration makes follow-through and the invalidation level especially important."
            }
            return "Independent evidence confirms the current direction; monitor whether both sources continue to agree."
        case .accountLeads:
            return "The creator view moved first and has no qualifying capital confirmation, so treat it as a thesis update rather than a funded market signal."
        case .moneyLeads:
            return "Public capital moved first; look for an independent Smart Account view before treating the move as broader confirmation."
        case .smartAccountNewView, .smartAccountShift, .smartAccountConsensus:
            return "This is a change in qualified investor views; compare its assumptions and invalidation condition with your holding plan."
        case .smartMoneyMovement:
            return "This is an observable public-capital change; monitor whether it persists and gains independent account support."
        }
    }

    private static func attentionReason(
        signal: PortfolioSignal,
        attention: PersonalizedAttentionLevel,
        relationship: PortfolioRelationship,
        weight: Double?,
        costDistance: Double?
    ) -> String {
        var factors: [String] = []
        if relationship == .position {
            factors.append(weight.map { "a \(percentText($0)) position" } ?? "a held position")
            if let costDistance { factors.append(costDistanceText(costDistance)) }
        } else {
            factors.append(relationship == .watchlist ? "a watched ticker" : "an untracked ticker")
        }

        switch signal.kind {
        case .divergence: factors.append("evidence is diverging")
        case .confirmation: factors.append("independent evidence agrees")
        case .accountLeads: factors.append("capital confirmation is absent")
        case .moneyLeads: factors.append("capital moved first")
        default: factors.append("a qualified source changed")
        }
        if signal.resolvedDataStatus == .delayed { factors.append("data is delayed") }

        return "Marked \(attention.label.lowercased()) because this is \(joinedFactors(factors))."
    }

    private static func joinedFactors(_ factors: [String]) -> String {
        guard let last = factors.last else { return "relevant to your portfolio" }
        if factors.count == 1 { return last }
        if factors.count == 2 { return factors.joined(separator: " and ") }
        return factors.dropLast().joined(separator: ", ") + ", and " + last
    }

    private static func percentText(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    private static func costDistanceText(_ value: Double) -> String {
        let magnitude = abs(value).formatted(.percent.precision(.fractionLength(1)))
        if abs(value) < 0.005 { return "near your cost" }
        return "\(magnitude) \(value > 0 ? "above" : "below") your cost"
    }
}
