import XCTest
@testable import BSmart

final class AppModelTests: XCTestCase {
    @MainActor
    func testAIAssistantGroundsPortfolioAndTickerResponsesInExistingModels() async throws {
        let suiteName = "BSmartTests.AI.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = AppModel(
            client: BundleBSmartAPIClient(),
            defaults: defaults,
            portfolioBootstrapStrategy: .remoteFallback
        )
        await model.load()

        let portfolio = AIResearchAssistant.answer(prompt: .portfolio, model: model)
        XCTAssertNotNil(portfolio.signal)
        XCTAssertFalse(portfolio.evidence.isEmpty)
        XCTAssertEqual(portfolio.ticker, model.personalizedPortfolioSignals.first?.signal.ticker)

        let ticker = AIResearchAssistant.answer(query: "What changed in NVDA?", model: model)
        XCTAssertEqual(ticker.ticker, "NVDA")
        XCTAssertTrue(ticker.signal != nil || !ticker.evidence.isEmpty)

        XCTAssertFalse(AIAssistantPrompt.allCases.map(\.title).contains {
            let title = $0.lowercased()
            return title.contains("diverg") || title.contains("disagree") || title.contains("confirm")
        })
        let activity = AIResearchAssistant.answer(prompt: .activity, model: model)
        let activityCopy = [activity.title, activity.summary, activity.context, activity.nextStep]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        XCTAssertFalse(activityCopy.contains("diverg"))
        XCTAssertFalse(activityCopy.contains("disagree"))
        XCTAssertFalse(activityCopy.contains("confirm"))
        XCTAssertTrue(Set(activity.evidence.map(\.source)).isSubset(of: ["Smart Account", "Smart Money"]))
    }

    @MainActor
    func testAppLanguagePreferencePersistsAndLocalizesDynamicCopy() throws {
        let suiteName = "BSmartTests.Language.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            BSmartLocalization.configure(.system)
        }

        let language = AppLanguageStore(defaults: defaults)
        XCTAssertEqual(language.selection, .system)

        language.select(.simplifiedChinese)
        XCTAssertEqual("Settings".bSmartLocalized, "设置")
        XCTAssertEqual("Score %@".bSmartLocalized("112"), "评分 112")
        XCTAssertEqual("Smart".bSmartLocalized, "Smart")
        XCTAssertEqual("Smart Account".bSmartLocalized, "Smart Account")
        XCTAssertEqual("Smart Money".bSmartLocalized, "Smart Money")
        XCTAssertEqual("Ask Mr Collie".bSmartLocalized, "询问 Mr Collie")
        XCTAssertEqual("Need attention".bSmartLocalized, "需关注")
        XCTAssertEqual("AI recent summary".bSmartLocalized, "AI 近期概括")
        XCTAssertEqual("Investment strategy profile".bSmartLocalized, "投资策略画像")
        XCTAssertEqual("Representative works".bSmartLocalized, "历史代表作")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let sampleDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 6,
            hour: 12
        )))
        XCTAssertTrue(sampleDate.bSmartDigestDate.contains("8月"))

        let restored = AppLanguageStore(defaults: defaults)
        XCTAssertEqual(restored.selection, .simplifiedChinese)

        restored.select(.english)
        XCTAssertEqual("Settings".bSmartLocalized, "Settings")
        XCTAssertTrue(sampleDate.bSmartDigestDate.contains("August"))
    }

    func testBundledMVPFixturesDecodeAndPreserveEvidenceReferences() async throws {
        let client = BundleBSmartAPIClient()

        async let signals = client.fetchSignals()
        async let accountUpdates = client.fetchSmartAccountUpdates()
        async let moneyMovements = client.fetchSmartMoneyMovements()
        async let intelligence = client.fetchTickerIntelligence()
        async let portfolio = client.fetchPortfolio()
        async let portfolioHistory = client.fetchPortfolioHistory()
        async let smartAccounts = client.fetchSmartAccounts()
        async let smartMoney = client.fetchSmartMoney()

        let loadedSignals = try await signals
        let loadedAccountUpdates = try await accountUpdates
        let loadedMoneyMovements = try await moneyMovements
        let loadedIntelligence = try await intelligence
        let loadedPortfolio = try await portfolio
        let loadedPortfolioHistory = try await portfolioHistory
        let loadedSmartAccounts = try await smartAccounts
        let loadedSmartMoney = try await smartMoney
        let accountIds = Set(loadedAccountUpdates.map(\.id))
        let moneyIds = Set(loadedMoneyMovements.map(\.id))

        XCTAssertEqual(loadedSignals.count, 5)
        XCTAssertGreaterThan(loadedAccountUpdates.count, 4)
        XCTAssertTrue(loadedAccountUpdates.allSatisfy { $0.evidenceURL != nil })
        XCTAssertTrue(loadedAccountUpdates.allSatisfy { !($0.originalText ?? "").isEmpty })
        XCTAssertGreaterThan(loadedMoneyMovements.count, 50)
        XCTAssertGreaterThan(Set(loadedMoneyMovements.map(\.accountId)).count, 10)
        XCTAssertTrue(loadedMoneyMovements.allSatisfy { $0.evidenceURL != nil })
        XCTAssertEqual(loadedIntelligence.count, 5)
        XCTAssertEqual(loadedPortfolio.count, 4)
        XCTAssertGreaterThan(loadedPortfolioHistory.count, 20)
        XCTAssertEqual(loadedPortfolioHistory, loadedPortfolioHistory.sorted { $0.timestamp < $1.timestamp })
        XCTAssertGreaterThan(loadedSmartAccounts.count, 100)
        XCTAssertTrue(loadedSmartAccounts.contains { $0.avatarURL != nil && $0.followersCount != nil })
        let rankedAccount = try XCTUnwrap(loadedSmartAccounts.first)
        let accountEvidence = try await client.fetchSmartAccountEvidence(accountID: rankedAccount.id)
        XCTAssertFalse(accountEvidence.isEmpty)
        XCTAssertTrue(accountEvidence.allSatisfy { $0.authorId == rankedAccount.id })
        XCTAssertTrue(accountEvidence.contains { !($0.evidenceSpan ?? "").isEmpty })
        XCTAssertTrue(accountEvidence.contains { $0.settlement?.actualHit != nil })
        let representativeWorks = accountEvidence.filter { $0.evidenceRole == "representative" }
        XCTAssertFalse(representativeWorks.isEmpty)
        XCTAssertLessThanOrEqual(representativeWorks.count, 3)
        XCTAssertEqual(Set(representativeWorks.map { $0.ticker.uppercased() }).count, representativeWorks.count)
        XCTAssertEqual(
            representativeWorks.compactMap(\.representativeTickerRank),
            Array(1...representativeWorks.count)
        )
        XCTAssertTrue(representativeWorks.allSatisfy { ($0.representativeTickerContribution ?? 0) > 0 })
        XCTAssertTrue(representativeWorks.allSatisfy { ($0.representativeCallCount ?? 0) > 0 })
        XCTAssertTrue(representativeWorks.allSatisfy { work in
            guard let priceEvidence = work.priceEvidence,
                  let markers = priceEvidence.opinionMarkers,
                  !priceEvidence.candles.isEmpty,
                  !markers.isEmpty else {
                return false
            }
            return markers.count <= 10
                && markers.allSatisfy { $0.contribution > 0 }
                && markers.allSatisfy { marker in
                    priceEvidence.candles.contains { $0.day == marker.viewDay }
                }
        })
        let rankedMoney = try XCTUnwrap(loadedSmartMoney.first)
        let moneyEvidence = try await client.fetchSmartMoneyEvidence(accountID: rankedMoney.id)
        XCTAssertFalse(moneyEvidence.isEmpty)
        XCTAssertLessThanOrEqual(moneyEvidence.count, 3)
        XCTAssertTrue(moneyEvidence.allSatisfy { $0.accountId == rankedMoney.id })
        XCTAssertEqual(
            moneyEvidence.map(\.representativeRank),
            Array(1...moneyEvidence.count)
        )
        XCTAssertTrue(moneyEvidence.allSatisfy { !$0.priceEvidence.candles.isEmpty })
        XCTAssertTrue(moneyEvidence.allSatisfy { !$0.priceEvidence.entryMarkers.isEmpty })
        XCTAssertTrue(moneyEvidence.allSatisfy { $0.priceEvidence.entryMarkers.count <= 10 })
        XCTAssertTrue(loadedPortfolio.allSatisfy { $0.resolvedKind == .position })
        XCTAssertEqual(loadedPortfolio.compactMap(\.portfolioWeight).reduce(0, +), 1, accuracy: 0.001)
        XCTAssertTrue(loadedSignals.allSatisfy { !$0.resolvedLimitations.isEmpty })
        XCTAssertEqual(Set(loadedSignals.map(\.resolvedDataStatus)), Set(SignalDataStatus.allCases))

        let divergence = try XCTUnwrap(loadedSignals.first { $0.kind == .divergence })
        XCTAssertEqual(Set(divergence.evidence.map(\.source)), [.smartAccount, .smartMoney])
        XCTAssertEqual(divergence.evidence(for: .smartAccount).count, 1)
        XCTAssertEqual(divergence.evidence(for: .smartMoney).count, 1)

        let accountOnly = try XCTUnwrap(loadedSignals.first { $0.kind == .accountLeads })
        XCTAssertEqual(accountOnly.smartMoneyCoverage, .unavailable)
        XCTAssertTrue(accountOnly.evidence(for: .smartMoney).isEmpty)

        let delayed = try XCTUnwrap(loadedSignals.first { $0.resolvedDataStatus == .delayed })
        XCTAssertEqual(delayed.kind, .moneyLeads)
        for evidence in loadedSignals.flatMap(\.evidence) {
            switch evidence.source {
            case .smartAccount:
                XCTAssertTrue(accountIds.contains(evidence.referenceId))
            case .smartMoney:
                XCTAssertTrue(moneyIds.contains(evidence.referenceId))
            }
        }
    }

    @MainActor
    func testTodaySmartAccountPreviewResolvesRankingAndThreeDistinctRepresentativeWorks() async throws {
        let suiteName = "BSmartTests.AccountPreview.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = AppModel(
            client: BundleBSmartAPIClient(),
            defaults: defaults,
            portfolioBootstrapStrategy: .remoteFallback
        )
        await model.load()

        let update = try XCTUnwrap(model.smartAccountUpdates.first { $0.authorId == "427693716" })
        let account = model.smartAccountProfile(for: update)
        XCTAssertEqual(account.name, "Trade With Insight")
        XCTAssertEqual(account.resolvedRank, 7)
        XCTAssertEqual(account.resolvedSettledCalls, 221)

        await model.loadSmartAccountEvidence(for: account)
        let works = model.representativeAccountEvidence(for: account, limit: 3)
        XCTAssertEqual(works.map(\.ticker), ["TSLA", "MU", "CRCL"])
        XCTAssertEqual(Set(works.map { $0.ticker.uppercased() }).count, 3)
        XCTAssertTrue(works.allSatisfy { $0.priceEvidence != nil })
        XCTAssertTrue(works.allSatisfy { $0.settlement?.status.lowercased() == "settled" })
    }

    @MainActor
    func testEvidenceFallsBackToBundledSnapshotsWhenLiveAPIIsUnavailable() async throws {
        let suiteName = "BSmartTests.EvidenceFallback.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let bundledClient = BundleBSmartAPIClient()
        let accounts = try await bundledClient.fetchSmartAccounts()
        let account = try XCTUnwrap(accounts.first { $0.id == "427693716" })
        let money = try await bundledClient.fetchSmartMoney()
        let moneyAccount = try XCTUnwrap(
            money.first { $0.id == "0x0ad9e656d9e6211d0ea1c5462342e1fc94cc4cbf" }
        )

        let model = AppModel(
            client: FailingBSmartAPIClient(),
            bootstrapFallbackClient: bundledClient,
            defaults: defaults
        )

        await model.loadSmartAccountEvidence(for: account)
        await model.loadSmartMoneyEvidence(for: moneyAccount)

        XCTAssertFalse(model.representativeAccountEvidence(for: account).isEmpty)
        XCTAssertFalse(model.moneyEvidence(for: moneyAccount).isEmpty)
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testOpportunitySignalsOnlyIncludeImportantUntrackedTickers() async throws {
        let suiteName = "BSmartTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = AppModel(
            client: BundleBSmartAPIClient(),
            defaults: defaults,
            portfolioBootstrapStrategy: .remoteFallback
        )
        await model.load()

        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.signals.count, 5)
        XCTAssertEqual(model.portfolioSignals.map(\.ticker), ["HOOD", "NVDA", "MSTR", "PLTR"])
        XCTAssertEqual(model.opportunitySignals.map(\.ticker), ["AVGO"])

        let opportunity = try XCTUnwrap(model.opportunitySignals.first)
        XCTAssertEqual(opportunity.kind, .accountLeads)
        XCTAssertEqual(opportunity.smartMoneyCoverage, .unavailable)
        XCTAssertEqual(Set(opportunity.evidence.map(\.source)), [.smartAccount])
    }

    @MainActor
    func testLocalOnlyFirstUseStartsEmptyAndPersistsCompletion() async throws {
        let suiteName = "BSmartTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstModel = AppModel(
            client: TestBSmartAPIClient(),
            defaults: defaults,
            portfolioBootstrapStrategy: .localOnly
        )
        await firstModel.load()

        XCTAssertTrue(firstModel.hasFinishedInitialLoad)
        XCTAssertTrue(firstModel.positions.isEmpty)
        XCTAssertFalse(firstModel.hasCompletedPortfolioSetup)
        XCTAssertFalse(firstModel.completePortfolioSetup())
        XCTAssertTrue(firstModel.savePortfolioEntry(
            id: nil,
            ticker: "NVDA",
            companyName: "NVIDIA",
            kind: .watchlist,
            shares: nil,
            averageCost: nil,
            portfolioWeight: nil
        ))
        XCTAssertTrue(firstModel.completePortfolioSetup())

        let restoredModel = AppModel(
            client: TestBSmartAPIClient(),
            defaults: defaults,
            portfolioBootstrapStrategy: .localOnly
        )
        await restoredModel.load()

        XCTAssertEqual(restoredModel.watchlist.map(\.ticker), ["NVDA"])
        XCTAssertTrue(restoredModel.hasCompletedPortfolioSetup)
    }

    @MainActor
    func testBrokeragePrototypeConnectionPersistsWithoutCredentials() throws {
        let suiteName = "BSmartTests.Brokerage.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstModel = AppModel(
            client: TestBSmartAPIClient(),
            defaults: defaults,
            portfolioBootstrapStrategy: .localOnly
        )
        XCTAssertTrue(firstModel.linkedBrokerageAccounts.isEmpty)

        let linked = firstModel.connectBrokeragePrototype(
            provider: .interactiveBrokers,
            detectedHoldingCount: 3,
            importedPositionCount: 2
        )

        XCTAssertEqual(linked.provider, .interactiveBrokers)
        XCTAssertEqual(linked.detectedHoldingCount, 3)
        XCTAssertEqual(linked.importedPositionCount, 2)
        XCTAssertTrue(linked.isPrototype)

        let restoredModel = AppModel(
            client: TestBSmartAPIClient(),
            defaults: defaults,
            portfolioBootstrapStrategy: .localOnly
        )
        XCTAssertEqual(restoredModel.linkedBrokerageAccounts, [linked])

        restoredModel.disconnectBrokerage(.interactiveBrokers)
        XCTAssertTrue(restoredModel.linkedBrokerageAccounts.isEmpty)
        XCTAssertNil(defaults.string(forKey: "brokerage-api-key"))
    }

    @MainActor
    func testCompletedSetupDoesNotRestartAfterPortfolioIsCleared() async throws {
        let suiteName = "BSmartTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = AppModel(
            client: TestBSmartAPIClient(),
            defaults: defaults,
            portfolioBootstrapStrategy: .localOnly
        )
        await model.load()
        XCTAssertTrue(model.savePortfolioEntry(
            id: nil,
            ticker: "NVDA",
            companyName: "NVIDIA",
            kind: .watchlist,
            shares: nil,
            averageCost: nil,
            portfolioWeight: nil
        ))
        XCTAssertTrue(model.completePortfolioSetup())
        model.deletePosition(id: try XCTUnwrap(model.positions.first?.id))

        let restoredModel = AppModel(
            client: TestBSmartAPIClient(),
            defaults: defaults,
            portfolioBootstrapStrategy: .localOnly
        )
        await restoredModel.load()

        XCTAssertTrue(restoredModel.positions.isEmpty)
        XCTAssertTrue(restoredModel.hasCompletedPortfolioSetup)
    }

    @MainActor
    func testLoadSortsSignalsAndComputesPortfolioValue() async throws {
        let suiteName = "BSmartTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = AppModel(client: TestBSmartAPIClient(), defaults: defaults)
        await model.load()

        XCTAssertEqual(model.positions.count, 1)
        XCTAssertEqual(model.portfolioValue, 250, accuracy: 0.001)
        XCTAssertEqual(model.signals.map(\.ticker), ["NEW", "OLD"])
        XCTAssertEqual(model.portfolioSignals.map(\.ticker), ["NEW"])
    }

    @MainActor
    func testLiveRefreshReplacesRealtimeCollectionsWithoutReloadingPortfolio() async throws {
        let suiteName = "BSmartTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let client = RefreshingBSmartAPIClient()
        let model = AppModel(client: client, defaults: defaults)

        await model.load()
        XCTAssertEqual(model.signals.first?.title, "Initial")
        let portfolioID = try XCTUnwrap(model.positions.first?.id)

        await model.refreshLiveIntelligence()

        XCTAssertEqual(model.signals.first?.title, "Realtime")
        XCTAssertEqual(model.positions.first?.id, portfolioID)
        XCTAssertFalse(model.isRefreshingLiveIntelligence)
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testManualPositionPersistsWithoutBackendMutation() async throws {
        let suiteName = "BSmartTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstModel = AppModel(client: TestBSmartAPIClient(), defaults: defaults)
        await firstModel.load()
        firstModel.addPosition(ticker: "nvda", companyName: "NVIDIA", shares: 2, averageCost: 100)

        let restoredModel = AppModel(client: TestBSmartAPIClient(), defaults: defaults)
        await restoredModel.load()

        XCTAssertEqual(restoredModel.positions.last?.ticker, "NVDA")
        XCTAssertEqual(restoredModel.positions.last?.currentPrice, 100)
    }

    @MainActor
    func testAddingExistingTickerUpdatesInsteadOfDuplicating() async throws {
        let suiteName = "BSmartTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = AppModel(client: TestBSmartAPIClient(), defaults: defaults)
        await model.load()
        model.addPosition(ticker: "new", companyName: "Updated", shares: 4, averageCost: 90)

        XCTAssertEqual(model.positions.count, 1)
        XCTAssertEqual(model.positions[0].shares, 4)
        XCTAssertEqual(model.positions[0].averageCost, 90)
        XCTAssertEqual(model.positions[0].currentPrice, 125)
    }

    @MainActor
    func testWatchlistEntryPersistsWithoutSyntheticPositionValues() async throws {
        let suiteName = "BSmartTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstModel = AppModel(client: TestBSmartAPIClient(), defaults: defaults)
        await firstModel.load()
        XCTAssertTrue(firstModel.savePortfolioEntry(
            id: nil,
            ticker: "nvda",
            companyName: "NVIDIA",
            kind: .watchlist,
            shares: nil,
            averageCost: nil,
            portfolioWeight: nil
        ))

        let restoredModel = AppModel(client: TestBSmartAPIClient(), defaults: defaults)
        await restoredModel.load()
        let watched = try XCTUnwrap(restoredModel.watchlist.first { $0.ticker == "NVDA" })
        XCTAssertEqual(watched.shares, 0)
        XCTAssertEqual(watched.averageCost, 0)
        XCTAssertNil(watched.portfolioWeight)
    }

    @MainActor
    func testPositionCanUseDeclaredWeightWithoutSharesOrCost() async throws {
        let suiteName = "BSmartTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = AppModel(client: TestBSmartAPIClient(), defaults: defaults)
        await model.load()
        XCTAssertTrue(model.savePortfolioEntry(
            id: nil,
            ticker: "PLTR",
            companyName: "Palantir",
            kind: .position,
            shares: nil,
            averageCost: nil,
            portfolioWeight: 0.35
        ))

        XCTAssertEqual(model.positionWeight(for: "PLTR"), 0.35, accuracy: 0.001)
        XCTAssertFalse(model.savePortfolioEntry(
            id: nil,
            ticker: "EMPTY",
            companyName: "Empty",
            kind: .position,
            shares: nil,
            averageCost: nil,
            portfolioWeight: nil
        ))
    }

    @MainActor
    func testWeightOnlyPositionDoesNotCreateFalsePortfolioValueOrReturn() async throws {
        let suiteName = "BSmartTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = AppModel(client: TestBSmartAPIClient(), defaults: defaults)
        await model.load()
        let original = try XCTUnwrap(model.positions.first)
        XCTAssertTrue(model.savePortfolioEntry(
            id: original.id,
            ticker: original.ticker,
            companyName: original.companyName,
            kind: .position,
            shares: nil,
            averageCost: nil,
            portfolioWeight: 0.35
        ))

        XCTAssertFalse(model.hasAnyPortfolioValuation)
        XCTAssertFalse(model.hasAnyPortfolioReturn)
        XCTAssertEqual(model.portfolioValue, 0, accuracy: 0.001)
        XCTAssertEqual(model.portfolioGain, 0, accuracy: 0.001)
        XCTAssertEqual(model.declaredPortfolioWeight, 0.35, accuracy: 0.001)
    }

    @MainActor
    func testMissingCostBasisDoesNotTreatMarketValueAsProfit() async throws {
        let suiteName = "BSmartTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = AppModel(client: TestBSmartAPIClient(), defaults: defaults)
        await model.load()
        let original = try XCTUnwrap(model.positions.first)
        XCTAssertTrue(model.savePortfolioEntry(
            id: original.id,
            ticker: original.ticker,
            companyName: original.companyName,
            kind: .position,
            shares: 2,
            averageCost: nil,
            portfolioWeight: nil
        ))

        XCTAssertTrue(model.hasAnyPortfolioValuation)
        XCTAssertFalse(model.hasAnyPortfolioReturn)
        XCTAssertEqual(model.portfolioValue, 250, accuracy: 0.001)
        XCTAssertEqual(model.portfolioGain, 0, accuracy: 0.001)
        XCTAssertEqual(model.portfolioGainPercent, 0, accuracy: 0.001)
    }

    @MainActor
    func testEditingPositionIntoWatchlistPreservesIdentity() async throws {
        let suiteName = "BSmartTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = AppModel(client: TestBSmartAPIClient(), defaults: defaults)
        await model.load()
        let original = try XCTUnwrap(model.positions.first)
        XCTAssertTrue(model.savePortfolioEntry(
            id: original.id,
            ticker: original.ticker,
            companyName: original.companyName,
            kind: .watchlist,
            shares: original.shares,
            averageCost: original.averageCost,
            portfolioWeight: 0.5
        ))

        let updated = try XCTUnwrap(model.positions.first)
        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.resolvedKind, .watchlist)
        XCTAssertEqual(updated.shares, 0)
        XCTAssertNil(updated.portfolioWeight)
    }

    @MainActor
    func testDeletePositionUsesStableIdentity() async throws {
        let suiteName = "BSmartTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = AppModel(client: TestBSmartAPIClient(), defaults: defaults)
        await model.load()
        let id = try XCTUnwrap(model.positions.first?.id)
        model.deletePosition(id: id)

        XCTAssertTrue(model.positions.isEmpty)
    }

    @MainActor
    func testPortfolioSignalsExcludeUnheldTickersAndPrioritizeSignalPriority() async throws {
        let suiteName = "BSmartTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = AppModel(client: RankingBSmartAPIClient(), defaults: defaults)
        await model.load()

        XCTAssertEqual(model.portfolioSignals.map(\.ticker), ["LIGHT", "HEAVY"])
        XCTAssertEqual(model.positionWeight(for: "HEAVY"), 10.0 / 11.0, accuracy: 0.001)
    }

    @MainActor
    func testAccountOnlySignalKeepsUnavailableMoneyCoverage() async throws {
        let suiteName = "BSmartTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = AppModel(client: AccountOnlyBSmartAPIClient(), defaults: defaults)
        await model.load()

        let signal = try XCTUnwrap(model.portfolioSignals.first)
        XCTAssertEqual(signal.kind, .accountLeads)
        XCTAssertEqual(signal.smartMoneyCoverage, .unavailable)
        XCTAssertEqual(Set(signal.evidence.map(\.source)), [.smartAccount])
    }

    @MainActor
    func testSignalUserStatePersistsAcrossAppModelInstances() async throws {
        let suiteName = "BSmartTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstModel = AppModel(client: TestBSmartAPIClient(), defaults: defaults)
        await firstModel.load()
        let signal = try XCTUnwrap(firstModel.portfolioSignals.first)

        firstModel.markSignalRead(signal.id)
        firstModel.toggleSignalSaved(signal.id)
        firstModel.setSignalFeedback(.useful, for: signal.id)

        let restoredModel = AppModel(client: TestBSmartAPIClient(), defaults: defaults)
        await restoredModel.load()
        let state = restoredModel.signalUserState(for: signal.id)

        XCTAssertTrue(state.isRead)
        XCTAssertTrue(state.isSaved)
        XCTAssertFalse(state.isIgnored)
        XCTAssertEqual(state.feedback, .useful)
    }

    @MainActor
    func testTodayActivityReadStatePersistsAcrossAppModelInstances() async throws {
        let suiteName = "BSmartTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let activityID = UUID()
        let firstModel = AppModel(client: TestBSmartAPIClient(), defaults: defaults)
        await firstModel.load()
        firstModel.markTodayActivityRead(activityID)

        let restoredModel = AppModel(client: TestBSmartAPIClient(), defaults: defaults)
        await restoredModel.load()

        XCTAssertTrue(restoredModel.isTodayActivityRead(activityID))
        restoredModel.markTodayActivityRead(activityID, isRead: false)
        XCTAssertFalse(restoredModel.isTodayActivityRead(activityID))
    }

    @MainActor
    func testIgnoredSignalLeavesFeedAndCanBeRestored() async throws {
        let suiteName = "BSmartTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = AppModel(client: TestBSmartAPIClient(), defaults: defaults)
        await model.load()
        let signal = try XCTUnwrap(model.portfolioSignals.first)

        model.ignoreSignal(signal.id)

        XCTAssertFalse(model.portfolioSignals.contains { $0.id == signal.id })
        XCTAssertTrue(model.ignoredPortfolioSignals.contains { $0.id == signal.id })

        model.restoreIgnoredSignal(signal.id)

        XCTAssertTrue(model.portfolioSignals.contains { $0.id == signal.id })
        XCTAssertFalse(model.ignoredPortfolioSignals.contains { $0.id == signal.id })
    }

    @MainActor
    func testBundledSnapshotBootstrapsFirstLaunchWhenLiveAPIIsUnavailable() async throws {
        let suiteName = "BSmartTests.OfflineBootstrap.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = AppModel(
            client: FailingBSmartAPIClient(),
            bootstrapFallbackClient: BundleBSmartAPIClient(),
            defaults: defaults
        )
        await model.load()

        XCTAssertTrue(model.hasFinishedInitialLoad)
        XCTAssertFalse(model.signals.isEmpty)
        XCTAssertFalse(model.smartAccounts.isEmpty)
        XCTAssertFalse(model.smartMoney.isEmpty)
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testCachedSignalsRemainReadableWhenRefreshFails() async throws {
        let suiteName = "BSmartTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let onlineModel = AppModel(client: TestBSmartAPIClient(), defaults: defaults)
        await onlineModel.load()
        XCTAssertFalse(onlineModel.portfolioSignals.isEmpty)

        let offlineModel = AppModel(client: FailingBSmartAPIClient(), defaults: defaults)
        await offlineModel.load()

        XCTAssertTrue(offlineModel.hasFinishedInitialLoad)
        XCTAssertFalse(offlineModel.portfolioSignals.isEmpty)
        XCTAssertNotNil(offlineModel.lastDataRefreshAt)
        XCTAssertNotNil(offlineModel.errorMessage)
    }

    @MainActor
    func testDailyDigestUsesPersistedSnapshotAndRestoresItOffline() async throws {
        let suiteName = "BSmartTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let onlineModel = AppModel(client: DigestBSmartAPIClient(), defaults: defaults)
        await onlineModel.load()

        XCTAssertEqual(onlineModel.personalizedPortfolioSignals.map(\.signal.title), ["Live view"])
        XCTAssertEqual(onlineModel.personalizedDailyDigestSignals.map(\.signal.title), ["Morning snapshot"])
        XCTAssertEqual(onlineModel.dailyDigestSnapshot?.summary, "One material change")

        let offlineModel = AppModel(client: FailingBSmartAPIClient(), defaults: defaults)
        await offlineModel.load()

        XCTAssertEqual(offlineModel.personalizedDailyDigestSignals.map(\.signal.title), ["Morning snapshot"])
        XCTAssertEqual(offlineModel.dailyDigestSnapshot?.summary, "One material change")
    }

    func testSignalDeepLinkParsesCustomAndUniversalURLs() throws {
        let signalID = try XCTUnwrap(UUID(uuidString: "4f0af9cc-4b5a-41b2-a8b4-2e61c5a40211"))
        let customURL = BSmartDeepLink.signalURL(for: signalID)
        let universalURL = try XCTUnwrap(URL(string: "https://bsmart.today/signals/\(signalID.uuidString)"))

        XCTAssertEqual(BSmartDeepLink.signalID(from: customURL), signalID)
        XCTAssertEqual(BSmartDeepLink.signalID(from: universalURL), signalID)
        XCTAssertNil(BSmartDeepLink.signalID(from: URL(string: "bsmart://portfolio")!))
    }

    @MainActor
    func testRouterResolvesPendingSignalIntoTodayNavigation() async throws {
        let signals = try await BundleBSmartAPIClient().fetchSignals()
        let signal = try XCTUnwrap(signals.first)
        let router = AppRouter()

        XCTAssertTrue(router.handle(url: BSmartDeepLink.signalURL(for: signal.id)))
        XCTAssertEqual(router.selection, .today)
        XCTAssertEqual(router.pendingSignalID, signal.id)

        router.resolvePendingSignal(from: signals)

        XCTAssertNil(router.pendingSignalID)
        XCTAssertFalse(router.todayPath.isEmpty)
    }

    @MainActor
    func testDailyDigestDeepLinkOpensTodayDigestRoute() throws {
        let router = AppRouter()
        let customURL = try XCTUnwrap(URL(string: "bsmart://today/digest"))
        let universalURL = try XCTUnwrap(URL(string: "https://bsmart.today/today/digest"))

        XCTAssertTrue(router.handle(url: customURL))
        XCTAssertEqual(router.selection, .today)
        XCTAssertNil(router.pendingSignalID)
        XCTAssertFalse(router.todayPath.isEmpty)

        XCTAssertTrue(BSmartDeepLink.isDailyDigest(universalURL))
        XCTAssertFalse(BSmartDeepLink.isDailyDigest(BSmartDeepLink.signalURL(for: UUID())))
    }

    @MainActor
    func testFollowedIntelligencePersistsAndSurfacesUntrackedSignals() async throws {
        let suiteName = "BSmartTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstModel = AppModel(
            client: BundleBSmartAPIClient(),
            defaults: defaults,
            portfolioBootstrapStrategy: .localOnly
        )
        await firstModel.load()

        let hoodSignal = try XCTUnwrap(firstModel.signals.first { $0.ticker == "HOOD" })
        let hoodEvidence = try XCTUnwrap(hoodSignal.evidence(for: .smartAccount).first)
        let hoodUpdate = try XCTUnwrap(firstModel.accountUpdate(id: hoodEvidence.referenceId))
        let account = try XCTUnwrap(firstModel.smartAccounts.first { $0.id == hoodUpdate.authorId })
        let pltrSignal = try XCTUnwrap(firstModel.signals.first { $0.ticker == "PLTR" })
        let pltrEvidence = try XCTUnwrap(pltrSignal.evidence(for: .smartMoney).first)
        let pltrMovement = try XCTUnwrap(firstModel.moneyMovement(id: pltrEvidence.referenceId))
        let money = try XCTUnwrap(firstModel.smartMoney.first { $0.id == pltrMovement.accountId })
        XCTAssertFalse(firstModel.isFollowingSmartAccount(account.id))
        XCTAssertFalse(firstModel.isFollowingSmartMoney(money.id))

        firstModel.toggleSmartAccountFollow(account.id)
        firstModel.toggleSmartMoneyFollow(money.id)

        XCTAssertEqual(Set(firstModel.followedIntelligenceSignals.map(\.ticker)), ["HOOD", "PLTR"])

        let restoredModel = AppModel(
            client: BundleBSmartAPIClient(),
            defaults: defaults,
            portfolioBootstrapStrategy: .localOnly
        )
        await restoredModel.load()

        XCTAssertTrue(restoredModel.isFollowingSmartAccount(account.id))
        XCTAssertTrue(restoredModel.isFollowingSmartMoney(money.id))
        XCTAssertTrue(restoredModel.savePortfolioEntry(
            id: nil,
            ticker: "HOOD",
            companyName: "Robinhood Markets",
            kind: .watchlist,
            shares: nil,
            averageCost: nil,
            portfolioWeight: nil
        ))
        XCTAssertEqual(restoredModel.followedIntelligenceSignals.map(\.ticker), ["PLTR"])
    }

    @MainActor
    func testResetLocalAppDataClearsPersonalStateAndRestartsSetup() async throws {
        let suiteName = "BSmartTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = AppModel(
            client: BundleBSmartAPIClient(),
            defaults: defaults,
            portfolioBootstrapStrategy: .localOnly
        )
        await model.load()
        XCTAssertTrue(model.savePortfolioEntry(
            id: nil,
            ticker: "NVDA",
            companyName: "NVIDIA",
            kind: .watchlist,
            shares: nil,
            averageCost: nil,
            portfolioWeight: nil
        ))
        XCTAssertTrue(model.completePortfolioSetup())
        let signal = try XCTUnwrap(model.signals.first)
        let account = try XCTUnwrap(model.smartAccounts.first)
        let money = try XCTUnwrap(model.smartMoney.first)
        model.toggleSignalSaved(signal.id)
        model.toggleSmartAccountFollow(account.id)
        model.toggleSmartMoneyFollow(money.id)
        model.markTodayActivityRead(UUID())

        await model.resetLocalAppData()

        XCTAssertTrue(model.positions.isEmpty)
        XCTAssertTrue(model.signalUserStates.isEmpty)
        XCTAssertTrue(model.readTodayActivityIDs.isEmpty)
        XCTAssertTrue(model.followedSmartAccountIDs.isEmpty)
        XCTAssertTrue(model.followedSmartMoneyIDs.isEmpty)
        XCTAssertFalse(model.hasCompletedPortfolioSetup)
        XCTAssertNil(defaults.object(forKey: "bsmart.portfolio.v1"))
        XCTAssertNil(defaults.object(forKey: "bsmart.portfolio-setup-complete.v1"))
        XCTAssertNil(defaults.object(forKey: "bsmart.signal-user-states.v1"))
        XCTAssertNil(defaults.object(forKey: "bsmart.today-read-activities.v1"))
        XCTAssertNil(defaults.object(forKey: "bsmart.client-cache.v1"))
        XCTAssertNil(defaults.object(forKey: "bsmart.followed-smart-accounts.v1"))
        XCTAssertNil(defaults.object(forKey: "bsmart.followed-smart-money.v1"))
    }

    func testPersonalizerElevatesHighWeightLosingDivergence() async throws {
        let signals = try await BundleBSmartAPIClient().fetchSignals()
        let signal = try XCTUnwrap(signals.first { $0.kind == .divergence })
        let position = PortfolioPosition(
            id: UUID(),
            ticker: signal.ticker,
            companyName: signal.companyName,
            shares: 20,
            averageCost: 100,
            currentPrice: 90,
            entryKind: .position,
            portfolioWeight: 0.32
        )

        let result = PortfolioSignalPersonalizer.personalize(
            signal: signal,
            position: position,
            resolvedWeight: 0.32
        )

        XCTAssertEqual(result.relationship, .position)
        XCTAssertEqual(result.attention, .priority)
        XCTAssertEqual(result.positionWeight, 0.32)
        XCTAssertEqual(try XCTUnwrap(result.costDistancePercent), -0.10, accuracy: 0.001)
        XCTAssertTrue(result.contextSummary.contains("32%"))
        XCTAssertTrue(result.contextSummary.contains("below your cost"))
        XCTAssertTrue(result.impactText.contains("public capital disagree"))
    }

    func testPersonalizerDoesNotInventMissingCostContext() async throws {
        let signals = try await BundleBSmartAPIClient().fetchSignals()
        let signal = try XCTUnwrap(signals.first)
        let position = PortfolioPosition(
            id: UUID(),
            ticker: signal.ticker,
            companyName: signal.companyName,
            shares: 5,
            averageCost: 0,
            currentPrice: 90,
            entryKind: .position,
            portfolioWeight: 0.12
        )

        let result = PortfolioSignalPersonalizer.personalize(
            signal: signal,
            position: position,
            resolvedWeight: 0.12
        )

        XCTAssertNil(result.costDistancePercent)
        XCTAssertTrue(result.contextSummary.contains("cost not entered"))
        XCTAssertTrue(result.impactText.contains("Add a cost basis"))
        XCTAssertFalse(result.impactText.contains("above your cost"))
        XCTAssertFalse(result.impactText.contains("below your cost"))
    }

    func testPersonalizerSeparatesWatchlistFromCapitalExposure() async throws {
        let signals = try await BundleBSmartAPIClient().fetchSignals()
        let signal = try XCTUnwrap(signals.first)
        let watched = PortfolioPosition(
            id: UUID(),
            ticker: signal.ticker,
            companyName: signal.companyName,
            shares: 0,
            averageCost: 0,
            currentPrice: 90,
            entryKind: .watchlist,
            portfolioWeight: nil
        )

        let result = PortfolioSignalPersonalizer.personalize(
            signal: signal,
            position: watched,
            resolvedWeight: 0
        )

        XCTAssertEqual(result.relationship, .watchlist)
        XCTAssertNil(result.positionWeight)
        XCTAssertEqual(result.contextSummary, "Watchlist · no capital exposed")
        XCTAssertTrue(result.impactText.contains("no portfolio capital is exposed"))
    }
}

private actor RefreshingBSmartAPIClient: BSmartAPIClient {
    private var signalFetches = 0
    private let positionID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!

    func fetchPortfolio() async throws -> [PortfolioPosition] {
        [PortfolioPosition(
            id: positionID,
            ticker: "NVDA",
            companyName: "NVIDIA",
            shares: 1,
            averageCost: 100,
            currentPrice: 120
        )]
    }

    func fetchSignals() async throws -> [PortfolioSignal] {
        signalFetches += 1
        let title = signalFetches == 1 ? "Initial" : "Realtime"
        return [PortfolioSignal(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!,
            ticker: "NVDA",
            companyName: "NVIDIA",
            title: title,
            summary: title,
            occurredAt: Date(timeIntervalSince1970: Double(signalFetches)),
            dataAsOf: Date(timeIntervalSince1970: Double(signalFetches)),
            priority: .important,
            kind: .smartMoneyMovement,
            direction: .bullish,
            smartMoneyCoverage: .available,
            conclusion: title,
            positionImpact: title,
            nextStep: title,
            evidence: []
        )]
    }

    func fetchSmartAccountUpdates() async throws -> [SmartAccountUpdate] { [] }
    func fetchSmartMoneyMovements() async throws -> [SmartMoneyMovement] { [] }
    func fetchTickerIntelligence() async throws -> [TickerIntelligence] { [] }
    func fetchSmartAccounts() async throws -> [SmartAccountProfile] { [] }
    func fetchSmartMoney() async throws -> [SmartMoneySignal] { [] }
}

private struct TestBSmartAPIClient: BSmartAPIClient {
    func fetchPortfolio() async throws -> [PortfolioPosition] {
        [PortfolioPosition(
            id: UUID(),
            ticker: "NEW",
            companyName: "Test",
            shares: 2,
            averageCost: 100,
            currentPrice: 125
        )]
    }

    func fetchSignals() async throws -> [PortfolioSignal] {
        [signal(ticker: "OLD", offset: -60), signal(ticker: "NEW", offset: 60)]
    }

    func fetchSmartAccountUpdates() async throws -> [SmartAccountUpdate] { [] }
    func fetchSmartMoneyMovements() async throws -> [SmartMoneyMovement] { [] }
    func fetchTickerIntelligence() async throws -> [TickerIntelligence] { [] }
    func fetchSmartAccounts() async throws -> [SmartAccountProfile] { [] }
    func fetchSmartMoney() async throws -> [SmartMoneySignal] { [] }

    private func signal(ticker: String, offset: TimeInterval) -> PortfolioSignal {
        PortfolioSignal(
            id: ticker == "NEW"
                ? UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
                : UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
            ticker: ticker,
            companyName: ticker,
            title: ticker,
            summary: ticker,
            occurredAt: Date(timeIntervalSince1970: offset),
            dataAsOf: Date(timeIntervalSince1970: offset),
            priority: .notable,
            kind: .confirmation,
            direction: .bullish,
            smartMoneyCoverage: .available,
            conclusion: ticker,
            positionImpact: ticker,
            nextStep: ticker,
            evidence: []
        )
    }
}

private struct FailingBSmartAPIClient: BSmartAPIClient {
    func fetchPortfolio() async throws -> [PortfolioPosition] { throw BSmartAPIError.invalidResponse }
    func fetchSignals() async throws -> [PortfolioSignal] { throw BSmartAPIError.invalidResponse }
    func fetchSmartAccountUpdates() async throws -> [SmartAccountUpdate] { throw BSmartAPIError.invalidResponse }
    func fetchSmartMoneyMovements() async throws -> [SmartMoneyMovement] { throw BSmartAPIError.invalidResponse }
    func fetchTickerIntelligence() async throws -> [TickerIntelligence] { throw BSmartAPIError.invalidResponse }
    func fetchSmartAccounts() async throws -> [SmartAccountProfile] { throw BSmartAPIError.invalidResponse }
    func fetchSmartMoney() async throws -> [SmartMoneySignal] { throw BSmartAPIError.invalidResponse }
}

private struct DigestBSmartAPIClient: BSmartAPIClient {
    private let ticker = "NVDA"

    func fetchPortfolio() async throws -> [PortfolioPosition] {
        [PortfolioPosition(
            id: UUID(),
            ticker: ticker,
            companyName: "NVIDIA",
            shares: 1,
            averageCost: 100,
            currentPrice: 110
        )]
    }

    func fetchSignals() async throws -> [PortfolioSignal] {
        [signal(title: "Live view", occurredAt: Date(timeIntervalSince1970: 200))]
    }

    func fetchDailyDigest() async throws -> DailyDigestSnapshot? {
        let generatedAt = Date(timeIntervalSince1970: 150)
        return DailyDigestSnapshot(
            id: UUID(),
            generatedAt: generatedAt,
            dataAsOf: generatedAt,
            periodStart: Date(timeIntervalSince1970: 50),
            periodEnd: generatedAt,
            title: "Your bSmart daily brief",
            summary: "One material change",
            signals: [signal(title: "Morning snapshot", occurredAt: Date(timeIntervalSince1970: 100))]
        )
    }

    func fetchSmartAccountUpdates() async throws -> [SmartAccountUpdate] { [] }
    func fetchSmartMoneyMovements() async throws -> [SmartMoneyMovement] { [] }
    func fetchTickerIntelligence() async throws -> [TickerIntelligence] { [] }
    func fetchSmartAccounts() async throws -> [SmartAccountProfile] { [] }
    func fetchSmartMoney() async throws -> [SmartMoneySignal] { [] }

    private func signal(title: String, occurredAt: Date) -> PortfolioSignal {
        PortfolioSignal(
            id: UUID(),
            ticker: ticker,
            companyName: "NVIDIA",
            title: title,
            summary: title,
            occurredAt: occurredAt,
            dataAsOf: occurredAt,
            priority: .important,
            kind: .accountLeads,
            direction: .bullish,
            smartMoneyCoverage: .unavailable,
            conclusion: title,
            positionImpact: title,
            nextStep: title,
            evidence: []
        )
    }
}

private struct RankingBSmartAPIClient: BSmartAPIClient {
    func fetchPortfolio() async throws -> [PortfolioPosition] {
        [
            PortfolioPosition(
                id: UUID(),
                ticker: "LIGHT",
                companyName: "Light",
                shares: 1,
                averageCost: 100,
                currentPrice: 100
            ),
            PortfolioPosition(
                id: UUID(),
                ticker: "HEAVY",
                companyName: "Heavy",
                shares: 10,
                averageCost: 100,
                currentPrice: 100
            ),
        ]
    }

    func fetchSignals() async throws -> [PortfolioSignal] {
        [
            signal(ticker: "HEAVY", priority: .notable),
            signal(ticker: "OUTSIDE", priority: .critical),
            signal(ticker: "LIGHT", priority: .critical),
        ]
    }

    func fetchSmartAccountUpdates() async throws -> [SmartAccountUpdate] { [] }
    func fetchSmartMoneyMovements() async throws -> [SmartMoneyMovement] { [] }
    func fetchTickerIntelligence() async throws -> [TickerIntelligence] { [] }
    func fetchSmartAccounts() async throws -> [SmartAccountProfile] { [] }
    func fetchSmartMoney() async throws -> [SmartMoneySignal] { [] }

    private func signal(ticker: String, priority: SignalPriority) -> PortfolioSignal {
        PortfolioSignal(
            id: UUID(),
            ticker: ticker,
            companyName: ticker,
            title: ticker,
            summary: ticker,
            occurredAt: Date(),
            dataAsOf: Date(),
            priority: priority,
            kind: .smartAccountNewView,
            direction: .bullish,
            smartMoneyCoverage: .unavailable,
            conclusion: ticker,
            positionImpact: ticker,
            nextStep: ticker,
            evidence: []
        )
    }
}

private struct AccountOnlyBSmartAPIClient: BSmartAPIClient {
    func fetchPortfolio() async throws -> [PortfolioPosition] {
        [PortfolioPosition(
            id: UUID(),
            ticker: "MSTR",
            companyName: "Strategy",
            shares: 1,
            averageCost: 400,
            currentPrice: 390
        )]
    }

    func fetchSignals() async throws -> [PortfolioSignal] {
        [PortfolioSignal(
            id: UUID(),
            ticker: "MSTR",
            companyName: "Strategy",
            title: "Risk limit changed",
            summary: "The thesis remains constructive.",
            occurredAt: Date(),
            dataAsOf: Date(),
            priority: .important,
            kind: .accountLeads,
            direction: .bullish,
            smartMoneyCoverage: .unavailable,
            conclusion: "No capital confirmation is available.",
            positionImpact: "Review the risk limit.",
            nextStep: "Read the source view.",
            evidence: [PortfolioSignalEvidence(
                id: UUID(),
                source: .smartAccount,
                referenceId: UUID(),
                actorName: "Creator",
                title: "Thesis updated",
                detail: "The invalidation level moved.",
                metric: "Score 89",
                observedAt: Date(),
                sourceURL: nil
            )]
        )]
    }

    func fetchSmartAccountUpdates() async throws -> [SmartAccountUpdate] { [] }
    func fetchSmartMoneyMovements() async throws -> [SmartMoneyMovement] { [] }
    func fetchTickerIntelligence() async throws -> [TickerIntelligence] { [] }
    func fetchSmartAccounts() async throws -> [SmartAccountProfile] { [] }
    func fetchSmartMoney() async throws -> [SmartMoneySignal] { [] }
}
