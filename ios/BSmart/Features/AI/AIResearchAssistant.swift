import Foundation

enum AIAssistantPrompt: String, CaseIterable, Identifiable {
    case portfolio
    case priority
    case activity
    case opportunity

    var id: Self { self }

    var title: String {
        switch self {
        case .portfolio: "What changed in my portfolio?"
        case .priority: "Which position needs attention?"
        case .activity: "What are Smart Account and Smart Money doing?"
        case .opportunity: "What new opportunity deserves research?"
        }
    }

    var symbol: String {
        switch self {
        case .portfolio: "rectangle.stack.fill"
        case .priority: "scope"
        case .activity: "waveform.path.ecg"
        case .opportunity: "sparkle.magnifyingglass"
        }
    }
}

struct AIAssistantEvidence: Identifiable, Hashable {
    let id: String
    let source: String
    let symbol: String
    let title: String
    let detail: String
    let metric: String?
}

struct AIAssistantResponse: Identifiable, Hashable {
    let id = UUID()
    let question: String
    let title: String
    let summary: String
    let context: String?
    let evidence: [AIAssistantEvidence]
    let nextStep: String
    let signal: PortfolioSignal?
    let ticker: String?
    let generatedRemotely: Bool
    let dataAsOf: Date?
}

@MainActor
enum AIResearchAssistant {
    static func response(
        from remote: MrCollieResponse,
        model: AppModel
    ) -> AIAssistantResponse {
        AIAssistantResponse(
            question: remote.question,
            title: remote.title,
            summary: remote.summary,
            context: remote.context,
            evidence: remote.evidence.map { item in
                AIAssistantEvidence(
                    id: item.id,
                    source: item.source,
                    symbol: item.sourceType.symbol,
                    title: item.title,
                    detail: item.detail,
                    metric: item.metric
                )
            },
            nextStep: remote.nextStep,
            signal: remote.signalId.flatMap { id in model.signals.first { $0.id == id } },
            ticker: remote.ticker,
            generatedRemotely: true,
            dataAsOf: remote.dataAsOf
        )
    }

    static func answer(
        prompt: AIAssistantPrompt,
        model: AppModel
    ) -> AIAssistantResponse {
        switch prompt {
        case .portfolio:
            portfolioBrief(model: model, question: prompt.title.bSmartLocalized)
        case .priority:
            priorityBrief(model: model, question: prompt.title.bSmartLocalized)
        case .activity:
            sourceActivityBrief(model: model, question: prompt.title.bSmartLocalized)
        case .opportunity:
            opportunityBrief(model: model, question: prompt.title.bSmartLocalized)
        }
    }

    static func answer(query: String, model: AppModel) -> AIAssistantResponse {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.lowercased()

        if let ticker = recognizedTicker(in: normalized, model: model) {
            return tickerBrief(ticker: ticker, model: model, question: trimmed)
        }
        if containsAny(normalized, values: ["risk", "attention", "priority", "风险", "关注", "优先"]) {
            return priorityBrief(model: model, question: trimmed)
        }
        if containsAny(normalized, values: [
            "smart account", "smart money", "author", "onchain", "account activity",
            "博主", "作者", "链上", "资金动态", "最新观点",
        ]) {
            return sourceActivityBrief(model: model, question: trimmed)
        }
        if containsAny(normalized, values: ["opportun", "new stock", "discover", "机会", "新标的", "发现"]) {
            return opportunityBrief(model: model, question: trimmed)
        }
        return portfolioBrief(model: model, question: trimmed)
    }

    private static func portfolioBrief(model: AppModel, question: String) -> AIAssistantResponse {
        let changes = model.personalizedPortfolioSignals
        guard let lead = changes.first else {
            return emptyResponse(
                question: question,
                title: "No qualified portfolio change".bSmartLocalized,
                summary: "There is no current Smart Account or Smart Money event tied to your positions or watchlist.".bSmartLocalized,
                nextStep: "Keep your portfolio details current so new evidence can be matched to your exposure.".bSmartLocalized
            )
        }

        let evidence = changes.prefix(3).compactMap { item -> AIAssistantEvidence? in
            guard let source = item.signal.evidence.first else { return nil }
            return AIAssistantEvidence(
                id: source.id.uuidString,
                source: source.source.label,
                symbol: source.source.symbol,
                title: "%@ · %@".bSmartLocalized(item.signal.ticker, source.title.bSmartLocalized),
                detail: source.detail.bSmartLocalized,
                metric: "Relevance %d".bSmartLocalized(item.personalization.relevanceScore)
            )
        }

        return AIAssistantResponse(
            question: question,
            title: "%d portfolio changes ranked by impact".bSmartLocalized(changes.count),
            summary: "The highest-priority source update concerns %@. Review each Smart Account view and Smart Money action on its own timestamp and horizon.".bSmartLocalized(lead.signal.ticker),
            context: lead.personalization.contextSummary.bSmartLocalized,
            evidence: evidence,
            nextStep: "Open the cited source and compare its assumptions with your cost basis and holding plan.".bSmartLocalized,
            signal: lead.signal,
            ticker: lead.signal.ticker,
            generatedRemotely: false,
            dataAsOf: lead.signal.dataAsOf
        )
    }

    private static func priorityBrief(model: AppModel, question: String) -> AIAssistantResponse {
        guard let lead = model.personalizedPortfolioSignals.first else {
            return emptyResponse(
                question: question,
                title: "No position needs immediate review".bSmartLocalized,
                summary: "No qualified event currently changes the evidence around your tracked portfolio.".bSmartLocalized,
                nextStep: "Review again after the next Smart Account or Smart Money update.".bSmartLocalized
            )
        }
        return response(for: lead, question: question)
    }

    private static func sourceActivityBrief(model: AppModel, question: String) -> AIAssistantResponse {
        let tracked = Set(model.positions.map { $0.ticker.uppercased() })
        let account = model.smartAccountUpdates
            .filter { tracked.contains($0.ticker.uppercased()) }
            .max { $0.publishedAt < $1.publishedAt }
        let money = model.smartMoneyMovements
            .filter { tracked.contains($0.ticker.uppercased()) }
            .max { $0.observedAt < $1.observedAt }

        var evidence: [AIAssistantEvidence] = []
        if let account {
            evidence.append(AIAssistantEvidence(
                id: account.id.uuidString,
                source: "Smart Account",
                symbol: SignalEvidenceSource.smartAccount.symbol,
                title: "%@ · %@".bSmartLocalized(account.ticker, account.authorName),
                detail: account.thesis.bSmartLocalized,
                metric: "Score %@".bSmartLocalized(account.score.formatted(.number.precision(.fractionLength(0))))
            ))
        }
        if let money {
            evidence.append(AIAssistantEvidence(
                id: money.id.uuidString,
                source: "Smart Money",
                symbol: SignalEvidenceSource.smartMoney.symbol,
                title: "%@ · %@".bSmartLocalized(money.ticker, money.publicIdentity.displayName),
                detail: "%@ %@ exposure on %@.".bSmartLocalized(
                    money.action.label,
                    money.direction.label,
                    money.market
                ),
                metric: "Notional change %@".bSmartLocalized(
                    abs(money.notionalChange).formatted(.currency(code: "USD").precision(.fractionLength(0)))
                )
            ))
        }

        guard !evidence.isEmpty else {
            return emptyResponse(
                question: question,
                title: "No recent source activity".bSmartLocalized,
                summary: "There is no recent Smart Account view or Smart Money action for your tracked tickers in the current dataset.".bSmartLocalized,
                nextStep: "Check again after the next source update.".bSmartLocalized
            )
        }

        return AIAssistantResponse(
            question: question,
            title: "Latest activity across your tracked tickers".bSmartLocalized,
            summary: "Smart Account views and Smart Money actions are shown as separate evidence streams because their participants, timestamps and horizons can differ.".bSmartLocalized,
            context: "Matched to your holdings and watchlist".bSmartLocalized,
            evidence: evidence,
            nextStep: "Open the source that matters to your holding plan and review its timestamp, horizon and limitations.".bSmartLocalized,
            signal: nil,
            ticker: evidence.count == 1 ? (account?.ticker ?? money?.ticker) : nil,
            generatedRemotely: false,
            dataAsOf: [account?.publishedAt, money?.observedAt].compactMap { $0 }.max()
        )
    }

    private static func opportunityBrief(model: AppModel, question: String) -> AIAssistantResponse {
        guard let signal = model.opportunitySignals.first else {
            return emptyResponse(
                question: question,
                title: "No qualified opportunity outside your portfolio".bSmartLocalized,
                summary: "Nothing outside your current positions and watchlist meets the current importance threshold.".bSmartLocalized,
                nextStep: "Keep the opportunity threshold strict and wait for independently supported evidence.".bSmartLocalized
            )
        }

        return AIAssistantResponse(
            question: question,
            title: "%@ is the leading research candidate".bSmartLocalized(signal.ticker),
            summary: neutralEvidenceSummary(for: signal),
            context: "Outside your current portfolio".bSmartLocalized,
            evidence: evidenceRows(signal.evidence),
            nextStep: "Open the cited source and compare its assumptions with the exposures you already hold.".bSmartLocalized,
            signal: signal,
            ticker: signal.ticker,
            generatedRemotely: false,
            dataAsOf: signal.dataAsOf
        )
    }

    private static func tickerBrief(
        ticker: String,
        model: AppModel,
        question: String
    ) -> AIAssistantResponse {
        if let signal = model.signals.first(where: { $0.ticker.caseInsensitiveCompare(ticker) == .orderedSame }) {
            let item = PersonalizedPortfolioSignal(
                signal: signal,
                personalization: model.personalization(for: signal)
            )
            return response(for: item, question: question)
        }

        guard let intelligence = model.intelligence.first(where: {
            $0.ticker.caseInsensitiveCompare(ticker) == .orderedSame
        }) else {
            return emptyResponse(
                question: question,
                title: "No supported evidence for %@".bSmartLocalized(ticker),
                summary: "This ticker is not in the current supported research universe.".bSmartLocalized,
                nextStep: "Try a ticker from your portfolio, watchlist, or the Tickers tab.".bSmartLocalized
            )
        }

        let evidence = [
            AIAssistantEvidence(
                id: "\(ticker)-account",
                source: "Smart Account",
                symbol: SignalEvidenceSource.smartAccount.symbol,
                title: intelligence.smartAccount.headline.bSmartLocalized,
                detail: intelligence.smartAccount.detail.bSmartLocalized,
                metric: "%d authors".bSmartLocalized(intelligence.smartAccount.qualifiedAuthorCount)
            ),
            AIAssistantEvidence(
                id: "\(ticker)-money",
                source: "Smart Money",
                symbol: SignalEvidenceSource.smartMoney.symbol,
                title: intelligence.smartMoney.headline.bSmartLocalized,
                detail: intelligence.smartMoney.detail.bSmartLocalized,
                metric: intelligence.smartMoney.coverage == .available
                    ? "%d accounts".bSmartLocalized(intelligence.smartMoney.qualifiedAccountCount)
                    : "No capital verification".bSmartLocalized
            ),
        ]

        return AIAssistantResponse(
            question: question,
            title: "%@ evidence overview".bSmartLocalized(ticker),
            summary: "Smart Account: %@ · Smart Money: %@".bSmartLocalized(
                intelligence.smartAccount.headline.bSmartLocalized,
                intelligence.smartMoney.headline.bSmartLocalized
            ),
            context: portfolioContext(ticker: ticker, model: model),
            evidence: evidence,
            nextStep: "Open the ticker research page to inspect each source before changing exposure.".bSmartLocalized,
            signal: nil,
            ticker: ticker,
            generatedRemotely: false,
            dataAsOf: intelligence.dataAsOf
        )
    }

    private static func response(
        for item: PersonalizedPortfolioSignal,
        question: String
    ) -> AIAssistantResponse {
        let signal = item.signal
        return AIAssistantResponse(
            question: question,
            title: "%@ needs your attention".bSmartLocalized(signal.ticker),
            summary: neutralEvidenceSummary(for: signal),
            context: item.personalization.contextSummary.bSmartLocalized,
            evidence: evidenceRows(signal.evidence),
            nextStep: "Open the cited source and compare its assumptions with your cost basis and holding plan.".bSmartLocalized,
            signal: signal,
            ticker: signal.ticker,
            generatedRemotely: false,
            dataAsOf: signal.dataAsOf
        )
    }

    private static func evidenceRows(
        _ evidence: [PortfolioSignalEvidence]
    ) -> [AIAssistantEvidence] {
        evidence.prefix(4).map { item in
            AIAssistantEvidence(
                id: item.id.uuidString,
                source: item.source.label,
                symbol: item.source.symbol,
                title: item.title.bSmartLocalized,
                detail: item.detail.bSmartLocalized,
                metric: item.metric?.bSmartLocalized
            )
        }
    }

    private static func neutralEvidenceSummary(for signal: PortfolioSignal) -> String {
        let sources = Set(signal.evidence.map(\.source))
        let sourceText: String
        if sources == [.smartAccount] {
            sourceText = "Smart Account"
        } else if sources == [.smartMoney] {
            sourceText = "Smart Money"
        } else {
            sourceText = "Smart Account and Smart Money"
        }
        return "%@ has %d recent %@ evidence items. Review each item on its own timestamp and horizon.".bSmartLocalized(
            signal.ticker,
            signal.evidence.count,
            sourceText
        )
    }

    private static func portfolioContext(ticker: String, model: AppModel) -> String? {
        guard let position = model.position(for: ticker) else {
            return "Outside your portfolio".bSmartLocalized
        }
        if position.isPosition {
            let weight = model.positionWeight(for: ticker)
            if position.averageCost > 0 {
                return "Held position · %@ of portfolio · cost %@".bSmartLocalized(
                    weight.formatted(.percent.precision(.fractionLength(0))),
                    position.averageCost.formatted(.currency(code: "USD"))
                )
            }
            return "Held position · %@ of portfolio".bSmartLocalized(
                weight.formatted(.percent.precision(.fractionLength(0)))
            )
        }
        return "Watchlist · no capital exposed".bSmartLocalized
    }

    private static func emptyResponse(
        question: String,
        title: String,
        summary: String,
        nextStep: String
    ) -> AIAssistantResponse {
        AIAssistantResponse(
            question: question,
            title: title,
            summary: summary,
            context: nil,
            evidence: [],
            nextStep: nextStep,
            signal: nil,
            ticker: nil,
            generatedRemotely: false,
            dataAsOf: nil
        )
    }

    private static func recognizedTicker(in query: String, model: AppModel) -> String? {
        let tickers = Set(
            model.positions.map(\.ticker)
                + model.intelligence.map(\.ticker)
                + model.signals.map(\.ticker)
        )
        return tickers
            .sorted { $0.count > $1.count }
            .first { ticker in
                let token = ticker.lowercased()
                return query.range(
                    of: "(?<![a-z0-9])\\Q\(token)\\E(?![a-z0-9])",
                    options: .regularExpression
                ) != nil
            }
    }

    private static func containsAny(_ value: String, values: [String]) -> Bool {
        values.contains { value.contains($0) }
    }

}
