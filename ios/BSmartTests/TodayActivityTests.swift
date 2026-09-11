import XCTest
@testable import BSmart

@MainActor
final class TodayActivityTests: XCTestCase {
    func testActivitiesUsePortfolioScopeAndKeepSourcesIndependent() throws {
        let held = PortfolioPosition(
            id: UUID(),
            ticker: "NVDA",
            companyName: "NVIDIA",
            shares: 10,
            averageCost: 100,
            currentPrice: 120,
            entryKind: .position,
            portfolioWeight: 0.4
        )
        let watched = PortfolioPosition(
            id: UUID(),
            ticker: "HOOD",
            companyName: "Robinhood",
            shares: 0,
            averageCost: 0,
            currentPrice: 70,
            entryKind: .watchlist
        )
        let account = makeAccountUpdate(ticker: "NVDA", author: "Author")
        let money = makeMoneyMovement(ticker: "NVDA", account: "Capital")
        let watchedAccount = makeAccountUpdate(ticker: "HOOD", author: "Watcher")

        let holdingActivities = TodayActivity.activities(
            scope: .holdings,
            positions: [held, watched],
            accountUpdates: [account, watchedAccount],
            moneyMovements: [money]
        )
        let watchlistActivities = TodayActivity.activities(
            scope: .watchlist,
            positions: [held, watched],
            accountUpdates: [account, watchedAccount],
            moneyMovements: [money]
        )

        XCTAssertEqual(Set(holdingActivities.map(\.ticker)), ["NVDA"])
        XCTAssertEqual(holdingActivities.filter(\.isSmartAccount).count, 1)
        XCTAssertEqual(holdingActivities.filter { !$0.isSmartAccount }.count, 1)
        XCTAssertEqual(watchlistActivities.map(\.ticker), ["HOOD"])
    }

    func testHigherPortfolioImpactRanksFirstWithinComparableEvidence() throws {
        let large = PortfolioPosition(
            id: UUID(),
            ticker: "NVDA",
            companyName: "NVIDIA",
            shares: 10,
            averageCost: 100,
            currentPrice: 120,
            entryKind: .position,
            portfolioWeight: 0.7
        )
        let small = PortfolioPosition(
            id: UUID(),
            ticker: "PLTR",
            companyName: "Palantir",
            shares: 2,
            averageCost: 100,
            currentPrice: 120,
            entryKind: .position,
            portfolioWeight: 0.1
        )

        let activities = TodayActivity.activities(
            scope: .holdings,
            positions: [large, small],
            accountUpdates: [
                makeAccountUpdate(ticker: "PLTR", author: "Small", timestamp: 90),
                makeAccountUpdate(ticker: "NVDA", author: "Large", timestamp: 100),
            ],
            moneyMovements: []
        )

        XCTAssertEqual(activities.first?.ticker, "NVDA")
    }

    func testLatestSortUsesOccurrenceTimeInsteadOfPortfolioWeight() throws {
        let large = makePosition(ticker: "NVDA", weight: 0.8)
        let small = makePosition(ticker: "PLTR", weight: 0.05)

        let activities = TodayActivity.activities(
            scope: .holdings,
            positions: [large, small],
            accountUpdates: [
                makeAccountUpdate(ticker: "NVDA", author: "Older", score: 99, percentile: 0.01, timestamp: 100),
                makeAccountUpdate(ticker: "PLTR", author: "Newer", score: 40, percentile: 0.6, timestamp: 200),
            ],
            moneyMovements: [],
            sort: .latest
        )

        XCTAssertEqual(activities.map(\.ticker), ["PLTR", "NVDA"])
    }

    func testSmartScoreSortNormalizesSourcesBeforeMixing() throws {
        let held = makePosition(ticker: "NVDA", weight: 0.4)
        let topAccount = makeAccountUpdate(
            ticker: "NVDA", author: "Top Account", score: 50, percentile: 0.05, timestamp: 100
        )
        let lowerAccount = makeAccountUpdate(
            ticker: "NVDA", author: "Lower Account", score: 90, percentile: 0.5, timestamp: 300
        )
        let topMoney = makeMoneyMovement(ticker: "NVDA", account: "Top Money", score: 35, timestamp: 200)
        let lowerMoney = makeMoneyMovement(ticker: "NVDA", account: "Lower Money", score: 20, timestamp: 400)

        let activities = TodayActivity.activities(
            scope: .holdings,
            positions: [held],
            accountUpdates: [lowerAccount, topAccount],
            moneyMovements: [lowerMoney, topMoney],
            sort: .smartScore
        )

        XCTAssertEqual(activities.prefix(2).map(\.actorKey), ["money:top money", "account:top account"])
    }

    func testRepeatedNewViewsAreGroupedButReversalStaysIndependent() throws {
        let held = makePosition(ticker: "NVDA", weight: 0.4)
        let first = makeAccountUpdate(ticker: "NVDA", author: "WallStTitan", timestamp: 100)
        let second = makeAccountUpdate(ticker: "NVDA", author: "WallStTitan", timestamp: 200)
        let reversal = makeAccountUpdate(
            ticker: "NVDA", author: "WallStTitan", lifecycle: .reversed, timestamp: 300
        )

        let activities = TodayActivity.activities(
            scope: .holdings,
            positions: [held],
            accountUpdates: [first, second, reversal],
            moneyMovements: []
        )

        XCTAssertEqual(activities.count, 2)
        let grouped = activities.compactMap { activity -> TodayAccountActivity? in
            guard case let .account(account) = activity, account.mentionCount > 1 else { return nil }
            return account
        }
        XCTAssertEqual(grouped.first?.mentionCount, 2)
    }

    func testRepeatedActorLimitKeepsAtMostTwoVisibleActivities() throws {
        let activities = (0..<4).map { index in
            TodayActivity.account(
                TodayAccountActivity(updates: [
                    makeAccountUpdate(
                        ticker: "NVDA",
                        author: "WallStTitan",
                        horizon: "\(index + 1)D",
                        timestamp: TimeInterval(400 - index)
                    )
                ])
            )
        }

        XCTAssertEqual(TodayActivity.limitingRepeatedActors(activities).count, 2)
    }

    func testLatestTrackedActivitiesKeepsOneNewestItemPerTrackedIdentity() throws {
        let activities = TodayActivity.latestTrackedActivities(
            accountUpdates: [
                makeAccountUpdate(ticker: "NVDA", author: "Tracked Author", timestamp: 100),
                makeAccountUpdate(ticker: "MSTR", author: "Tracked Author", timestamp: 300),
                makeAccountUpdate(ticker: "PLTR", author: "Untracked Author", timestamp: 500),
            ],
            moneyMovements: [
                makeMoneyMovement(ticker: "NVDA", account: "Tracked Capital", timestamp: 200),
                makeMoneyMovement(ticker: "MU", account: "Tracked Capital", timestamp: 400),
                makeMoneyMovement(ticker: "TSLA", account: "Other Capital", timestamp: 600),
            ],
            followedAccountIDs: ["tracked author"],
            followedMoneyIDs: ["TRACKED CAPITAL"]
        )

        XCTAssertEqual(activities.count, 2)
        XCTAssertEqual(activities.map(\.actorKey), ["money:tracked capital", "account:tracked author"])
        XCTAssertEqual(activities.map(\.ticker), ["MU", "MSTR"])
    }

    func testTrackedActivityResolvesProfileIDToPublicAuthorName() throws {
        let profile = SmartAccountProfile(
            id: "profile-123",
            name: "Serenity",
            handle: "@aleabitoreddit",
            platform: "X",
            score: 120,
            scoreChange: 0,
            specialty: "Technology",
            horizon: "60D",
            recentTicker: "AAOI"
        )
        let update = makeAccountUpdate(ticker: "AAOI", author: "Serenity", timestamp: 300)

        let activities = TodayActivity.latestTrackedActivities(
            accountUpdates: [update],
            moneyMovements: [],
            smartAccounts: [profile],
            followedAccountIDs: [profile.id],
            followedMoneyIDs: []
        )

        XCTAssertEqual(activities.count, 1)
        XCTAssertEqual(activities.first?.ticker, "AAOI")
    }

    func testAccountTitleIncludesDecisionInformation() throws {
        let update = makeAccountUpdate(ticker: "NVDA", author: "Author")
        let activity = TodayActivity.account(TodayAccountActivity(updates: [update]))

        XCTAssertTrue(activity.informativeTitle.contains("NVDA"))
        XCTAssertTrue(activity.informativeTitle.contains("$150"))
        XCTAssertTrue(activity.informativeTitle.contains("Demand is improving"))
        XCTAssertFalse(activity.informativeTitle.contains("published a"))
    }

    func testNearbyOpeningFillsAreGroupedIntoOneInformativeActivity() throws {
        let held = PortfolioPosition(
            id: UUID(),
            ticker: "NVDA",
            companyName: "NVIDIA",
            shares: 10,
            averageCost: 100,
            currentPrice: 120,
            entryKind: .position,
            portfolioWeight: 0.4
        )
        let movements = [
            makeMoneyMovement(ticker: "NVDA", account: "Capital", amount: 35_000, timestamp: 100),
            makeMoneyMovement(ticker: "NVDA", account: "Capital", amount: 36_000, timestamp: 90),
            makeMoneyMovement(ticker: "NVDA", account: "Capital", amount: 37_000, timestamp: 80),
            makeMoneyMovement(ticker: "NVDA", account: "Capital", amount: 35_000, timestamp: 70),
        ]

        let activities = TodayActivity.activities(
            scope: .holdings,
            positions: [held],
            accountUpdates: [],
            moneyMovements: movements
        )

        XCTAssertEqual(activities.count, 1)
        guard case let .money(activity) = try XCTUnwrap(activities.first) else {
            return XCTFail("Expected a Smart Money activity")
        }
        XCTAssertEqual(activity.transactionCount, 4)
        XCTAssertEqual(activity.notionalChange, 143_000, accuracy: 0.01)
        let title = TodayActivity.money(activity).informativeTitle
        XCTAssertTrue(title.contains("NVDA"))
        XCTAssertTrue(title.contains("$143.0K"))
    }

    func testViewpointPackagesRequireDifferentSmartAccounts() throws {
        let repeatedAuthor = [
            makeAccountUpdate(ticker: "NVDA", author: "Same", timestamp: 200),
            makeAccountUpdate(ticker: "NVDA", author: "Same", horizon: "60D", timestamp: 100),
        ]

        XCTAssertTrue(TodayViewpointPackage.packages(from: repeatedAuthor).isEmpty)

        let packages = TodayViewpointPackage.packages(
            from: repeatedAuthor + [makeAccountUpdate(ticker: "NVDA", author: "Different", timestamp: 300)]
        )

        XCTAssertEqual(packages.count, 1)
        XCTAssertEqual(packages[0].ticker, "NVDA")
        XCTAssertEqual(packages[0].accountCount, 2)
        XCTAssertEqual(packages[0].updates.count, 2)
    }

    func testViewpointPackagePreservesMixedDirectionEvidence() throws {
        let packages = TodayViewpointPackage.packages(from: [
            makeAccountUpdate(ticker: "MSTR", author: "Bull", direction: .bullish, timestamp: 200),
            makeAccountUpdate(ticker: "MSTR", author: "Bear", direction: .bearish, timestamp: 100),
        ])

        let package = try XCTUnwrap(packages.first)
        XCTAssertEqual(package.bullishCount, 1)
        XCTAssertEqual(package.bearishCount, 1)
        XCTAssertTrue(package.localizedHeadline.contains("MSTR"))
    }

    func testPackagePreviewUsesLatestHighRankedAuthorWithoutDiscardingOtherEvidence() throws {
        let updates = [
            makeAccountUpdate(ticker: "NVDA", author: "Highest", percentile: 0.01, timestamp: 100),
            makeAccountUpdate(ticker: "NVDA", author: "Latest qualified", percentile: 0.20, timestamp: 200),
            makeAccountUpdate(ticker: "NVDA", author: "Latest unqualified", percentile: 0.80, timestamp: 300),
        ]
        let package = try XCTUnwrap(TodayViewpointPackage.packages(from: updates).first)
        XCTAssertEqual(package.previewUpdate?.authorId, "Latest qualified")
        XCTAssertEqual(package.updates.count, 3)
        XCTAssertEqual(package.rankedUpdates.first?.authorId, "Highest")
        XCTAssertEqual(package.latestPreviewAuthors.map(\.authorId), ["Latest unqualified", "Latest qualified", "Highest"])
    }

    func testPackagePreviewAcceptsPercentageRanksAndFallsBackToBestAvailableAuthor() {
        let older = makeAccountUpdate(ticker: "NVDA", author: "Older", percentile: 8, timestamp: 100)
        let latest = makeAccountUpdate(ticker: "NVDA", author: "Latest", percentile: 25, timestamp: 200)
        let package = TodayViewpointPackage(ticker: "NVDA", companyName: "NVIDIA", updates: [older, latest])
        XCTAssertEqual(package.previewUpdate?.id, latest.id)

        let fallback = makeAccountUpdate(ticker: "NVDA", author: "Fallback", percentile: 0.30)
        let empty = TodayViewpointPackage(ticker: "NVDA", companyName: "NVIDIA", updates: [])
        XCTAssertNil(empty.previewUpdate)
        XCTAssertEqual(TodayViewpointPackage(ticker: "NVDA", companyName: "NVIDIA", updates: [fallback]).previewUpdate?.id, fallback.id)
    }

    func testSmartAlphaExcludesTrackedAndCrowdedTickers() throws {
        let updates = [
            makeAccountUpdate(ticker: "NVDA", author: "Tracked", percentile: 0.02, timestamp: 400, hasEvidence: true),
            makeAccountUpdate(ticker: "DELL", author: "Crowd A", percentile: 0.02, timestamp: 390, hasEvidence: true),
            makeAccountUpdate(ticker: "DELL", author: "Crowd B", percentile: 0.03, timestamp: 380, hasEvidence: true),
            makeAccountUpdate(ticker: "DELL", author: "Crowd C", percentile: 0.04, timestamp: 370, hasEvidence: true),
            makeAccountUpdate(ticker: "NBIS", author: "Discoverer", percentile: 0.03, timestamp: 360, hasEvidence: true),
        ]

        let opportunities = TodayAlphaOpportunity.opportunities(
            accountUpdates: updates,
            moneyMovements: [],
            excluding: ["NVDA"]
        )

        XCTAssertEqual(opportunities.map(\.ticker), ["NBIS"])
        XCTAssertEqual(opportunities.first?.sourceCount, 1)
    }

    func testSmartAlphaReturnsIndependentAccountAndMoneyCandidates() throws {
        let opportunities = TodayAlphaOpportunity.opportunities(
            accountUpdates: [
                makeAccountUpdate(ticker: "NBIS", author: "Discoverer", percentile: 0.02, timestamp: 400, hasEvidence: true),
            ],
            moneyMovements: [
                makeMoneyMovement(ticker: "CRCL", account: "Capital", amount: 800_000, score: 91, timestamp: 390, hasEvidence: true),
            ],
            excluding: []
        )

        XCTAssertEqual(Set(opportunities.map(\.ticker)), ["NBIS", "CRCL"])
        XCTAssertEqual(Set(opportunities.map(\.kind)), [.smartAccount, .smartMoney])
    }

    func testSourceHeadlinesPreserveConditionsAndSeparateAuthors() throws {
        let previous = BSmartLocalization.language
        BSmartLocalization.configure(.simplifiedChinese)
        defer { BSmartLocalization.configure(previous) }
        var bull = makeAccountUpdate(ticker: "META", author: "Unknown A", timestamp: 300)
        bull.activityTitleZH = "META：关注事件前上涨机会。"
        var bear = makeAccountUpdate(ticker: "META", author: "Unknown B", direction: .bearish, timestamp: 100)
        bear.activityTitleZH = "META：担忧诉讼拖累近期表现。"
        let package = try XCTUnwrap(TodayViewpointPackage.packages(from: [bull, bear]).first)
        XCTAssertEqual(package.sourceHeadlines.map(\.sourceName), ["Unknown A", "Unknown B"])
        XCTAssertTrue(package.localizedHeadline.contains("诉讼"))
        XCTAssertTrue(package.localizedHeadline.contains("事件前"))
        XCTAssertFalse(package.localizedHeadline.contains("Unknown"))
        XCTAssertFalse(package.localizedHeadline.contains("核心判断分化"))
    }

    func testSourceHeadlineKeepsShortAndLongTermQualifiers() {
        let previous = BSmartLocalization.language
        BSmartLocalization.configure(.simplifiedChinese)
        defer { BSmartLocalization.configure(previous) }
        var update = makeAccountUpdate(ticker: "NBIS", author: "Unknown")
        update.activityTitleZH = "加强 NBIS 判断：作者预计短期反弹至240–260美元，但长期仍看空。若重回阻力位，再考虑增加空头。"
        let headline = TodaySourceHeadline.account(update)
        XCTAssertTrue(headline.text.hasPrefix("预计"))
        XCTAssertTrue(headline.text.contains("长期仍看空"))
        XCTAssertTrue(headline.text.contains("若重回阻力位"))
        XCTAssertFalse(headline.text.contains("加强 NBIS 判断"))
    }

    func testSourceHeadlineAvoidsLegacyTruncationAndBlankTranslation() {
        let previous = BSmartLocalization.language
        BSmartLocalization.configure(.simplifiedChinese)
        defer { BSmartLocalization.configure(previous) }
        var update = makeAccountUpdate(ticker: "NBIS", author: "Unknown")
        update.activityTitleZH = "短期反弹，但…"
        update.translatedTextZH = "  "
        update.activityTitleEN = "Short-term rebound, but remains bearish longer term."
        XCTAssertEqual(TodaySourceHeadline.account(update).text, update.activityTitleEN)
    }

    func testAlphaMoneyHeadlinesKeepIndividualPositionsInsteadOfCrowdingClaim() throws {
        let opportunities = TodayAlphaOpportunity.opportunities(accountUpdates: [], moneyMovements: [
            makeMoneyMovement(ticker: "NVDA", account: "One", amount: 50000, timestamp: 300, hasEvidence: true),
            makeMoneyMovement(ticker: "NVDA", account: "Two", amount: 90000, timestamp: 200, hasEvidence: true)
        ], excluding: [])
        let alpha = try XCTUnwrap(opportunities.first)
        XCTAssertEqual(alpha.sourceHeadlines.count, 2)
        XCTAssertEqual(Set(alpha.sourceHeadlines.map(\.sourceName)).count, 2)
        XCTAssertTrue(alpha.localizedHeadline.contains("50.0K"))
        XCTAssertTrue(alpha.localizedHeadline.contains("90.0K"))
        XCTAssertFalse(alpha.localizedHeadline.contains("crowded"))
    }

    func testTrendingPagesPairCardsWithoutDroppingOrDuplicatingTickers() {
        let packages = ["NVDA", "MU", "MSTR", "HOOD", "PLTR"].map {
            TodayViewpointPackage(ticker: $0, companyName: $0, updates: [makeAccountUpdate(ticker: $0, author: "Author")])
        }
        let pages = TodayViewpointPage.pages(from: packages)
        XCTAssertEqual(pages.map { $0.packages.count }, [2, 2, 1])
        XCTAssertEqual(pages.map(\.index), [0, 1, 2])
        XCTAssertEqual(pages.map(\.id), ["NVDA", "MSTR", "PLTR"])
        XCTAssertEqual(pages.flatMap(\.packages), packages)
        XCTAssertTrue(TodayViewpointPage.pages(from: []).isEmpty)
        XCTAssertEqual(TodayViewpointPage.pages(from: Array(packages.prefix(1))).first?.packages.count, 1)
        XCTAssertEqual(TodayViewpointPage.pages(from: Array(packages.prefix(4))).map { $0.packages.count }, [2, 2])
    }

    private func makePosition(ticker: String, weight: Double) -> PortfolioPosition {
        PortfolioPosition(
            id: UUID(),
            ticker: ticker,
            companyName: ticker,
            shares: 10,
            averageCost: 100,
            currentPrice: 120,
            entryKind: .position,
            portfolioWeight: weight
        )
    }

    private func makeAccountUpdate(
        ticker: String,
        author: String,
        score: Double = 100,
        percentile: Double = 0.1,
        lifecycle: SmartAccountLifecycle = .new,
        direction: SignalDirection = .bullish,
        horizon: String = "20D",
        timestamp: TimeInterval = 100,
        hasEvidence: Bool = false
    ) -> SmartAccountUpdate {
        SmartAccountUpdate(
            id: UUID(),
            ticker: ticker,
            companyName: ticker,
            authorId: author,
            authorName: author,
            platform: "X",
            score: score,
            platformPercentile: percentile,
            direction: direction,
            lifecycle: lifecycle,
            horizon: horizon,
            targetPrice: 150,
            thesis: "Demand is improving.",
            invalidation: "Demand weakens.",
            publishedAt: Date(timeIntervalSince1970: timestamp),
            evidenceURL: hasEvidence ? URL(string: "https://example.com/evidence") : nil
        )
    }

    private func makeMoneyMovement(
        ticker: String,
        account: String,
        amount: Double = 50_000,
        score: Double = 80,
        timestamp: TimeInterval = 100,
        hasEvidence: Bool = false
    ) -> SmartMoneyMovement {
        SmartMoneyMovement(
            id: UUID(),
            ticker: ticker,
            companyName: ticker,
            accountId: account,
            accountLabel: account,
            accountScore: score,
            market: "xyz:\(ticker)",
            action: .opened,
            direction: .bullish,
            notionalBefore: 0,
            notionalAfter: amount,
            notionalChange: amount,
            leverage: 2,
            observedAt: Date(timeIntervalSince1970: timestamp),
            evidenceURL: hasEvidence ? URL(string: "https://example.com/capital") : nil
        )
    }
}
