import XCTest
@testable import BSmart

final class TodayInvestorActivityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testGroupsAllTickersUnderInvestorAndPreservesLatestOrdering() throws {
        let first = update("NVDA", age: 20)
        let second = update("MU", age: 40)
        let third = update("MSTR", age: 80)
        let group = try XCTUnwrap(groups([third, first, second]).first)
        XCTAssertEqual(group.id, "account:x:author")
        XCTAssertEqual(group.activities.map(\.id), [first.id, second.id, third.id])
        XCTAssertEqual(group.preview.map(\.ticker), ["NVDA", "MU"])
        XCTAssertEqual(group.name, "Same display name")
    }

    func testSourcePlatformAndIDsKeepUnrelatedPeopleSeparate() {
        let result = groups([update("NVDA"), update("MU", author: "other"),
                             update("TSLA", platform: "YouTube")], [movement("NVDA")])
        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(Set(result.map(\.id)), ["account:x:author", "account:x:other",
                                             "account:youtube:author", "money:author"])
    }

    func testCaseAndPlatformAliasesResolveSameIdentity() {
        let result = groups([update("NVDA", author: " AUTHOR ", platform: "Twitter"),
                             update("MU", platform: "X")])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.activities.count, 2)
    }

    func testDeduplicatesEventsWithoutDroppingReversalsOrDifferentMarkets() throws {
        let bullish = update("NVDA", age: 500)
        let reversed = update("NVDA", age: 100, direction: .bearish, lifecycle: .reversed)
        let money = movement("NVDA")
        let otherMarket = movement("NVDA", market: "other:NVDA")
        let result = groups([bullish, bullish, reversed], [money, money, otherMarket])
        let account = try XCTUnwrap(result.first { $0.source == .accounts })
        XCTAssertEqual(account.activities.count, 2)
        XCTAssertEqual(account.latest.direction, .bearish)
        XCTAssertEqual(result.first { $0.source == .money }?.activities.count, 2)
    }

    func testRealWindowIncludesBoundaryButNotFutureOrExpiredData() {
        let boundary = update("MU", age: 30 * 86_400)
        let result = groups([boundary, update("NVDA", age: 30 * 86_400 + 1), update("TSLA", age: -1)],
                            [movement("NVDA", age: 30 * 86_400 + 1), movement("NVDA", age: -1)])
        XCTAssertEqual(result.flatMap(\.activities).map(\.id), [boundary.id])
        XCTAssertTrue(groups([]).isEmpty)
    }

    func testNewestInvestorFirstAndStableUnderInputReordering() {
        let values = [update("NVDA", author: "a", age: 200), update("MU", author: "b", age: 100),
                      update("MSTR", author: "c", age: 100)]
        let money = movement("NVDA", age: 50)
        let result = groups(values, [money])
        XCTAssertEqual(result.map(\.id), ["money:author", "account:x:b", "account:x:c", "account:x:a"])
        XCTAssertEqual(result, groups(Array(values.reversed()), [money]))
    }

    func testPreviewShowsNewestInvestorFromEachAvailablePlatform() {
        let values = [update("TSLA", author: "yt-a", age: 10, platform: "YouTube"),
                      update("AMD", author: "yt-b", age: 20, platform: "YouTube"),
                      update("MRVL", author: "x-a", age: 30, platform: "X"),
                      update("QQQ", author: "reddit-a", age: 40, platform: "Reddit")]
        let all = groups(values)
        XCTAssertEqual(TodayInvestorActivity.previewAccounts(from: all).map(\.id),
                       ["account:youtube:yt-a", "account:x:x-a", "account:reddit:reddit-a"])
        XCTAssertEqual(TodayInvestorActivity.previewAccounts(from: groups(Array(values.prefix(3)))).map(\.id),
                       ["account:youtube:yt-a", "account:youtube:yt-b", "account:x:x-a"])
    }

    func testSourceAndSearchIntersectWithoutHidingOtherTickerContext() throws {
        let account = try XCTUnwrap(groups([update("NVDA"), update("MU")]).first)
        XCTAssertTrue(account.matches(source: .accounts, query: " nvda "))
        XCTAssertTrue(account.matches(source: .all, query: "DISPLAY"))
        XCTAssertFalse(account.matches(source: .money, query: "NVDA"))
        XCTAssertFalse(account.matches(source: .all, query: "unknown"))
        XCTAssertEqual(account.activities.count, 2)
        let money = try XCTUnwrap(groups([], [movement("NVDA")]).first)
        XCTAssertTrue(money.matches(source: .money, query: ""))
    }

    func testFullHistoryBacktestSnapshotUsesEarliestCapturedOpinion() throws {
        let serenity = profile(id: "1940360837547565056")
        let wey = profile(id: "1707559719215489024")
        let serenityStats = try XCTUnwrap(SmartAccountFollowBacktestSnapshot.stats(for: serenity))
        let weyStats = try XCTUnwrap(SmartAccountFollowBacktestSnapshot.stats(for: wey))
        XCTAssertEqual(serenityStats.startDay, "2025-09-30")
        XCTAssertEqual(serenityStats.endDay, "2026-08-13")
        XCTAssertEqual(serenityStats.tradeCount, 65)
        XCTAssertEqual(serenityStats.tradeHitRate, 37.0 / 65.0, accuracy: 0.0001)
        XCTAssertEqual(serenityStats.winLossCounts?.wins, 37)
        XCTAssertEqual(serenityStats.winLossCounts?.losses, 28)
        XCTAssertEqual(serenityStats.totalReturn, 1.2034211, accuracy: 0.0001)
        XCTAssertEqual(weyStats.startDay, "2025-07-21")
        XCTAssertEqual(weyStats.tradeCount, 42)
        XCTAssertEqual(weyStats.tradeHitRate, 27.0 / 42.0, accuracy: 0.0001)
        XCTAssertEqual(weyStats.winLossCounts?.wins, 27)
        XCTAssertEqual(weyStats.winLossCounts?.losses, 15)
        let mattStats = try XCTUnwrap(SmartAccountFollowBacktestSnapshot.stats(
            for: profile(id: "1365048046141267970")))
        XCTAssertEqual(mattStats.signalCount, 60)
        XCTAssertEqual(mattStats.tradeCount, 4)
        XCTAssertEqual(mattStats.winLossCounts?.wins, 3)
        XCTAssertEqual(mattStats.winLossCounts?.losses, 1)
        XCTAssertNil(SmartAccountFollowBacktestSnapshot.stats(for: profile(id: "missing")))
    }

    func testRoundedHitRateDoesNotInventWinLossCounts() {
        let stats = SmartAccountFollowBacktest(
            source: "x", investorID: "author", startDay: "2026-01-01", endDay: "2026-08-13",
            signalCount: 7, tradeCount: 7, tradeHitRate: 0.29, totalReturn: 0.1)
        XCTAssertNil(stats.winLossCounts)
    }

    func testCurrentBacktestOverridesBundledSnapshot() throws {
        var author = profile(id: "1940360837547565056")
        author.followBacktest = SmartAccountFollowBacktest(
            source: "x", investorID: author.id, startDay: "2025-09-30", endDay: "2026-09-01",
            signalCount: 100, tradeCount: 70, tradeHitRate: 0.6, totalReturn: 1.3)
        XCTAssertEqual(SmartAccountFollowBacktestSnapshot.stats(for: author)?.endDay, "2026-09-01")
    }

    func testVerifiedNativeTraderMapsIntoInvestorAndActivitySurfacesWithoutInventingRank() throws {
        let json = """
        {
          "profiles": [{"publicID":"11111111-1111-4111-8111-111111111111",
            "nickname":"Connor","handle":"imconnorzhang","avatarURL":null,"bio":"",
            "recentTicker":"NVDA","closedTrades":2,"wins":1,"realizedReturn":0.04,
            "netPnlUSD":4.0,"rank":null,"percentile":null,"asOf":"2026-09-28T00:00:00Z"}],
          "updates": [{"id":"22222222-2222-4222-8222-222222222222",
            "publicID":"11111111-1111-4111-8111-111111111111","nickname":"Connor",
            "avatarURL":null,"ticker":"NVDA","reducing":false,"side":"long",
            "body":"I expect earnings growth.","publishedAt":"2026-09-28T00:00:00Z",
            "rank":null,"percentile":null}]
        }
        """
        let snapshot = try BSmartJSONCoding.makeDecoder().decode(NativeInvestorSnapshot.self, from: Data(json.utf8))
        try snapshot.validate()
        let profile = try XCTUnwrap(snapshot.profiles.first?.smartAccount)
        let update = try XCTUnwrap(snapshot.updates.first?.smartAccountUpdate)
        XCTAssertEqual(profile.id, "bsmart:11111111-1111-4111-8111-111111111111")
        XCTAssertEqual(profile.nativePerformance?.losses, 1)
        XCTAssertNil(profile.nativePerformance?.rank)
        XCTAssertEqual(TodayInvestorDiscovery(accounts: [profile]).investors.map(\.account.id), [profile.id])
        XCTAssertEqual(update.authorId, profile.id)
        XCTAssertEqual(update.sourceKind, "native_opinion")
        let groups = TodayInvestorActivity.groups(accountUpdates: [update], moneyMovements: [],
                                                  now: update.publishedAt.addingTimeInterval(10))
        XCTAssertEqual(groups.first?.name, "Connor")
        XCTAssertEqual(groups.first?.activities.first?.ticker, "NVDA")
    }

    func testNativeInvestorSnapshotTreatsLegacyNullReducingAsOpeningTrade() throws {
        let json = """
        {"profiles":[{"publicID":"11111111-1111-4111-8111-111111111111",
          "nickname":"Connor","handle":"imconnorzhang","avatarURL":null,"bio":"",
          "recentTicker":"ORCL","closedTrades":0,"wins":0,"realizedReturn":null,
          "netPnlUSD":0,"rank":null,"percentile":null,"asOf":null}],
         "updates":[{"id":"22222222-2222-4222-8222-222222222222",
          "publicID":"11111111-1111-4111-8111-111111111111","nickname":"Connor",
          "avatarURL":null,"ticker":"ORCL","reducing":null,"side":"long",
          "body":"Bullish on ORCL","publishedAt":"2026-09-28T00:00:00Z",
          "rank":null,"percentile":null,
          "trade":{"sourceKind":"opinion","status":"open","marketCoin":"xyz:ORCL",
            "side":"long","notionalUSD":"25","leverage":5,"unrealizedPnlUSD":"1.25",
            "realizedPnlUSD":null,"entryPriceUSD":"138","currentPriceUSD":"140",
            "exitPriceUSD":null,"base":{"opinionID":"33333333-3333-4333-8333-333333333333",
              "authorID":"analyst-1","ticker":"ORCL","companyName":"Oracle",
              "platform":"x","direction":"bullish","publishedAt":"2026-09-27T00:00:00Z",
              "sourceURL":"https://example.com/orcl","thesis":"Bullish thesis",
              "authorName":"Analyst","avatarURL":null,"body":"Original ORCL opinion"}}}]}
        """
        let snapshot = try BSmartJSONCoding.makeDecoder().decode(NativeInvestorSnapshot.self, from: Data(json.utf8))
        try snapshot.validate()
        XCTAssertFalse(try XCTUnwrap(snapshot.updates.first).reducing)
        XCTAssertEqual(snapshot.updates.first?.smartAccountUpdate.direction, .bullish)
        let trade = try XCTUnwrap(snapshot.updates.first?.smartAccountUpdate.nativeTrade)
        XCTAssertTrue(trade.isOpen)
        XCTAssertEqual(trade.leverage, 5)
        XCTAssertEqual(trade.base?.body, "Original ORCL opinion")
        XCTAssertEqual(trade.base?.linkedUpdate?.id.uuidString,
                       "33333333-3333-4333-8333-333333333333")
        XCTAssertEqual(trade.base?.linkedUpdate?.sourceURL?.absoluteString,
                       "https://example.com/orcl")
    }

    func testNativeDirectCloseHasRealizedMetricsWithoutQuotedOpinion() throws {
        let json = """
        {"sourceKind":"direct","status":"closed","marketCoin":"xyz:ORCL","side":"short",
         "notionalUSD":"100","leverage":null,"unrealizedPnlUSD":null,
         "realizedPnlUSD":"-2.50","entryPriceUSD":null,"currentPriceUSD":null,
         "exitPriceUSD":"139.50","base":null}
        """
        let trade = try BSmartJSONCoding.makeDecoder().decode(NativeTradeContext.self, from: Data(json.utf8))
        XCTAssertTrue(trade.isClosed)
        XCTAssertNil(trade.base)
        XCTAssertEqual(trade.realizedPnlUSD, "-2.50")
        XCTAssertEqual(trade.exitPriceUSD, "139.50")
        XCTAssertTrue(trade.isClosingRecord)
    }

    func testSettledOriginalOpeningRetainsEntryAndOpeningIdentity() throws {
        let json = """
        {"sourceKind":"direct","eventKind":"opening","status":"closed","marketCoin":"xyz:AAPL","side":"long",
         "notionalUSD":"11.96928","leverage":null,"unrealizedPnlUSD":null,
         "realizedPnlUSD":"-0.024832","entryPriceUSD":"332.48","currentPriceUSD":null,
         "exitPriceUSD":"331.85","base":null}
        """
        let trade = try BSmartJSONCoding.makeDecoder().decode(NativeTradeContext.self, from: Data(json.utf8))
        XCTAssertTrue(trade.isClosed)
        XCTAssertFalse(trade.isOpen)
        XCTAssertFalse(trade.isClosingRecord)
        XCTAssertEqual(trade.notionalUSD, "11.96928")
        XCTAssertEqual(trade.entryPriceUSD, "332.48")
        XCTAssertEqual(trade.exitPriceUSD, "331.85")
        XCTAssertEqual(trade.realizedPnlUSD, "-0.024832")
    }

    func testNativeTradeCanLinkToPublishedSubjectEvent() throws {
        let json = """
        {"sourceKind":"direct","status":"open","marketCoin":"xyz:AAPL","side":"long",
         "notionalUSD":"11.97","leverage":3,"unrealizedPnlUSD":"0.00504",
         "realizedPnlUSD":null,"entryPriceUSD":"332.48","currentPriceUSD":"332.62",
         "exitPriceUSD":null,"base":{"kind":"subject","subjectID":"politician:H001082",
           "eventID":"congress:trade:house_20035491_g0","authorName":"Kevin Hern",
           "avatarURL":null,"body":"sell AAPL",
           "subjectEvent":{"id":"congress:trade:house_20035491_g0",
             "subjectID":"politician:H001082","ticker":"AAPL","type":"trade",
             "action":"sell","occurredDay":"2026-09-08","displayDay":"2026-09-25",
             "amountRange":"$1,001 - $15,000","isSample":false}}}
        """
        let trade = try BSmartJSONCoding.makeDecoder().decode(NativeTradeContext.self, from: Data(json.utf8))
        XCTAssertEqual(trade.base?.subjectEvent?.ticker, "AAPL")
        XCTAssertEqual(trade.base?.subjectEvent?.subjectID, "politician:H001082")
        XCTAssertNil(trade.base?.linkedUpdate)
    }

    func testSubjectFeedCombinesKindsAndUsesMarkedSampleMetricsUntilRealMetricsArrive() throws {
        let json = """
        {"schemaVersion":1,"snapshotAt":"2026-09-28T00:00:00Z","subjects":[
          {"id":"politician:7","kind":"politician","name":"Member A","avatarURL":null,"metrics":null},
          {"id":"celebrity:8","kind":"celebrity","name":"Figure B","avatarURL":null,
           "metrics":{"wins":12,"losses":3,"trackedReturn":0.15}},
          {"id":"institution:9","kind":"institution","name":"Fund C","avatarURL":null,"metrics":null}],
         "events":[
          {"id":"p1","subjectID":"politician:7","ticker":"AAPL","type":"trade","action":"buy",
           "occurredDay":"2026-09-20","displayDay":"2026-09-27","amountRange":null,
           "assetDescription":null,"isSample":false},
          {"id":"p2","subjectID":"politician:7","ticker":"NVDA","type":"trade","action":"sell",
           "occurredDay":"2026-09-21","displayDay":"2026-09-26","amountRange":null,
           "assetDescription":null,"isSample":false},
          {"id":"c1","subjectID":"celebrity:8","ticker":"MSFT","type":"opinion",
           "direction":"bullish","summary":"A market view",
           "occurredDay":"2026-09-25","displayDay":"2026-09-28","amountRange":null,
           "assetDescription":null,"isSample":true},
          {"id":"i1","subjectID":"institution:9","ticker":"TSLA","type":"trade","action":"sell",
           "occurredDay":"2026-09-22","displayDay":"2026-09-29","amountRange":null,
           "assetDescription":null,"isSample":true}]}
        """
        let snapshot = try JSONDecoder().decode(TodaySubjectFeedSnapshot.self, from: Data(json.utf8))
        XCTAssertTrue(snapshot.isValid)
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-29T12:00:00Z"))
        let groups = TodaySubjectActivity.groups(from: snapshot, now: date)
        XCTAssertEqual(groups.map(\.id), ["institution:9", "celebrity:8", "politician:7"])
        XCTAssertEqual(groups.last?.preview.map(\.ticker), ["AAPL", "NVDA"])
        XCTAssertTrue(try XCTUnwrap(groups.last).hasSampleMetrics)
        XCTAssertGreaterThan(try XCTUnwrap(groups.last).metrics.wins, 0)
        XCTAssertFalse(groups[1].hasSampleMetrics)
        XCTAssertEqual(groups[1].metrics.wins, 12)
        XCTAssertTrue(groups[1].matches(query: "msft"))
        let fullHistory = try XCTUnwrap(TodaySubjectActivity.history(for: "politician:7", in: snapshot))
        XCTAssertEqual(fullHistory.events.map(\.id), ["p1", "p2"])
        XCTAssertNil(TodaySubjectActivity.history(for: "politician:missing", in: snapshot))
    }

    func testSubjectEventCopyDistinguishesTradesHoldingsAndOpinions() throws {
        let previousLanguage = BSmartLocalization.language
        BSmartLocalization.configure(.simplifiedChinese)
        defer { BSmartLocalization.configure(previousLanguage) }

        func event(_ fields: String) throws -> TodaySubjectEvent {
            let json = """
            {"id":"event","subjectID":"subject",
             "occurredDay":"2026-06-30","displayDay":"2026-08-15","isSample":false,\(fields)}
            """
            return try JSONDecoder().decode(TodaySubjectEvent.self, from: Data(json.utf8))
        }

        let trade = try event("\"type\":\"trade\",\"ticker\":\"PBA\",\"action\":\"sell\",\"amountRange\":\"$15,001 - $50,000\"")
        XCTAssertEqual(TodaySubjectEventCopy.headline(for: trade, subjectKind: .politician),
                       "卖出 PBA · $15K-$50K")
        XCTAssertEqual(TodaySubjectEventCopy.compactAmountRange("$1,000,001 - $5,000,000"), "$1M-$5M")
        XCTAssertEqual(TodaySubjectEventCopy.compactAmountRange("$1,500,000 - $2,000,000"), "$1.5M-$2M")
        XCTAssertEqual(TodaySubjectEventCopy.compactAmountRange("undisclosed"), "undisclosed")
        XCTAssertTrue(TodaySubjectEventCopy.context(for: trade).contains("交易"))
        XCTAssertTrue(TodaySubjectEventCopy.context(for: trade).contains("公开"))

        let holding = try event("\"type\":\"holding\",\"underlyingTicker\":\"MU\",\"assetName\":\"MICRON\",\"action\":\"increased\",\"summary\":\"PUT option\"")
        XCTAssertEqual(TodaySubjectEventCopy.headline(for: holding, subjectKind: .celebrity),
                       "持仓较上期增加：MU 看跌期权")
        XCTAssertEqual(TodaySubjectEventCopy.headline(for: holding, subjectKind: .institution),
                       "持仓较上期增加：MU 看跌期权")
        XCTAssertTrue(TodaySubjectEventCopy.context(for: holding).contains("截至"))

        let held = try event("\"type\":\"holding\",\"assetName\":\"Unmapped Corp\",\"action\":\"held\"")
        XCTAssertEqual(TodaySubjectEventCopy.headline(for: held, subjectKind: .institution), "持有：Unmapped Corp")
        let omitted = try event("\"type\":\"holding\",\"ticker\":\"TSLA\",\"action\":\"no_longer_reported\"")
        XCTAssertEqual(TodaySubjectEventCopy.headline(for: omitted, subjectKind: .institution), "本期未列出：TSLA")

        let opinion = try event("\"type\":\"opinion\",\"ticker\":\"NVDA\",\"direction\":\"bullish\",\"summary\":\"需求增长尚未结束\"")
        XCTAssertEqual(TodaySubjectEventCopy.headline(for: opinion, subjectKind: .celebrity),
                       "看多 NVDA：需求增长尚未结束")

        BSmartLocalization.configure(.english)
        XCTAssertEqual(TodaySubjectEventCopy.headline(for: trade, subjectKind: .politician),
                       "Sell PBA · $15K-$50K")
        XCTAssertEqual(TodaySubjectEventCopy.headline(for: holding, subjectKind: .celebrity),
                       "Holding increased: MU Put option")
    }

    func testTrendingRanksSharedRecentTickerAheadOfFresherIsolatedTicker() {
        let actors = groups([
            update("AAPL", author: "a", age: 2 * 86_400),
            update("AAPL", author: "b", age: 2 * 86_400 + 60),
            update("TSLA", author: "c", age: 60),
        ])
        let items = actors.map { TodayHomeFeedItem.investor($0) }
        let latest = TodayHomeFeedOrder.sorted(items, trending: false, timeSort: .newest, now: now)
        let trending = TodayHomeFeedOrder.sorted(items, trending: true, timeSort: .newest, now: now)
        XCTAssertEqual(latest.first?.ticker, "TSLA")
        XCTAssertEqual(trending.first?.ticker, "AAPL")
        XCTAssertEqual(TodayHomeFeedOrder.sorted(items, trending: false, timeSort: .oldest, now: now).first?.ticker,
                       "AAPL")
    }

    func testFeedSplitsByEventAndOnlyFoldsAdjacentSameAsset() throws {
        let actor = try XCTUnwrap(groups([
            update("AAPL", age: 10), update("AAPL", age: 20), update("AAPL", age: 30),
            update("MSFT", age: 40), update("AAPL", age: 50),
        ]).first)
        let items = actor.activities.map {
            TodayHomeFeedItem.investor(.init(id: actor.id, activities: [$0]))
        }
        let cards = TodayHomeFeedItem.mergeAdjacent(items)
        XCTAssertEqual(cards.count, 3)
        guard case let .investor(first) = cards[0] else { return XCTFail("Expected investor card") }
        XCTAssertEqual(first.activities.map(\.ticker), ["AAPL", "AAPL", "AAPL"])
        XCTAssertEqual(Set(cards.map(\.id)).count, cards.count)
    }

    func testConsecutiveRunsFoldAfterTwoCardsAndCountMergedEvents() {
        let actors = groups([
            update("NVDA", author: "a", age: 10),
            update("MSFT", author: "a", age: 20),
            update("TSLA", author: "a", age: 30),
            update("AAPL", author: "a", age: 40),
            update("AAPL", author: "a", age: 50),
            update("QQQ", author: "b", age: 60),
        ])
        let items = actors.flatMap { actor in
            actor.activities.map { TodayHomeFeedItem.investor(.init(id: actor.id, activities: [$0])) }
        }
        let sorted = TodayHomeFeedOrder.sorted(TodayHomeFeedItem.mergeAdjacent(items),
                                               trending: false, timeSort: .newest, now: now)
        let runs = TodayHomeFeedRun.consecutive(sorted)
        XCTAssertEqual(runs.map(\.actorID), ["account:x:a", "account:x:b"])
        XCTAssertEqual(runs[0].actorName, "Same display name")
        XCTAssertEqual(runs[0].items.count, 4)
        XCTAssertEqual(runs[0].hiddenEventCount, 3)
        XCTAssertEqual(runs[1].hiddenEventCount, 0)
        XCTAssertEqual(runs.flatMap(\.items).map(\.id), sorted.map(\.id))
    }

    func testConsecutiveRunsNeverFoldAcrossAnotherActor() {
        let actors = groups([
            update("NVDA", author: "a", age: 10),
            update("MSFT", author: "a", age: 20),
            update("QQQ", author: "b", age: 30),
            update("TSLA", author: "a", age: 40),
            update("AAPL", author: "a", age: 50),
            update("MU", author: "a", age: 60),
        ])
        let items = actors.flatMap { actor in
            actor.activities.map { TodayHomeFeedItem.investor(.init(id: actor.id, activities: [$0])) }
        }
        let sorted = TodayHomeFeedOrder.sorted(items, trending: false, timeSort: .newest, now: now)
        let runs = TodayHomeFeedRun.consecutive(sorted)
        XCTAssertEqual(runs.map(\.actorID), ["account:x:a", "account:x:b", "account:x:a"])
        XCTAssertEqual(runs.map(\.items.count), [2, 1, 3])
        XCTAssertEqual(runs.map(\.hiddenEventCount), [0, 0, 1])
    }

    func testFeedPriceReferenceUsesEventDayOrNextNearbySession() {
        let evidence = SmartAccountPriceEvidence(
            ticker: "AAPL", viewDay: "2026-09-01", viewPrice: 99,
            latestDay: "2026-09-25", latestPrice: 120, responsePercent: nil,
            source: "test", candles: [
                PriceCandle(day: "2026-09-01", open: 98, high: 101, low: 97, close: 100, volume: 1),
                PriceCandle(day: "2026-09-04", open: 104, high: 106, low: 103, close: 105, volume: 1),
            ])
        XCTAssertEqual(TodayFeedPriceChange.startPrice(in: evidence, day: "2026-09-01"), 99)
        XCTAssertEqual(TodayFeedPriceChange.startPrice(in: evidence, day: "2026-09-02"), 105)
        XCTAssertNil(TodayFeedPriceChange.startPrice(in: evidence, day: "2026-08-20"))
    }

    func testFeedCurrentPriceUsesDollarSignWithoutCurrencyCode() {
        XCTAssertEqual(TodayFeedPriceChange.formattedPrice(85.83), "$85.83")
        XCTAssertEqual(TodayFeedPriceChange.formattedPrice(0.00518), "$0.00518")
    }

    func testOlder13FHoldingIsFindableWithoutInventedTicker() throws {
        let json = """
        {"schemaVersion":1,"snapshotAt":null,
         "subjects":[{"id":"celebrity:michael-burry","kind":"celebrity","name":"Michael Burry",
                      "avatarURL":null,"metrics":null}],
         "events":[{"id":"13f:1","subjectID":"celebrity:michael-burry","ticker":null,
                    "assetName":"PALANTIR TECHNOLOGIES INC","type":"holding","action":"held",
                    "occurredDay":"2025-09-30","displayDay":"2025-11-03",
                    "sourceURL":"https://www.sec.gov/Archives/example","isSample":false}]}
        """
        let snapshot = try JSONDecoder().decode(TodaySubjectFeedSnapshot.self, from: Data(json.utf8))
        XCTAssertTrue(snapshot.isValid)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-29T12:00:00Z"))
        let activity = try XCTUnwrap(TodaySubjectActivity.groups(from: snapshot, now: now).first)
        XCTAssertNil(activity.latest.ticker)
        XCTAssertEqual(activity.latest.displayAsset, "PALANTIR TECHNOLOGIES INC")
        XCTAssertTrue(activity.matches(query: "palantir"))
        XCTAssertTrue(TodaySubjectActivity.groups(from: snapshot,
            now: now.addingTimeInterval(100 * 86_400)).isEmpty)
    }

    private func profile(id: String) -> SmartAccountProfile {
        SmartAccountProfile(id: id, name: "Author", handle: "@author", platform: "X", score: 120,
                            scoreChange: 0, specialty: "Equities", horizon: "20D", recentTicker: nil)
    }

    private func groups(_ accounts: [SmartAccountUpdate], _ money: [SmartMoneyMovement] = []) -> [TodayInvestorActivity] {
        TodayInvestorActivity.groups(accountUpdates: accounts, moneyMovements: money, now: now)
    }

    private func update(_ ticker: String, author: String = "author", age: TimeInterval = 100,
                        platform: String = "X", direction: SignalDirection = .bullish,
                        lifecycle: SmartAccountLifecycle = .new) -> SmartAccountUpdate {
        SmartAccountUpdate(id: UUID(), ticker: ticker, companyName: ticker, authorId: author,
                           authorName: "Same display name", platform: platform, score: 120, platformPercentile: 0.1,
                           direction: direction, lifecycle: lifecycle, horizon: "20D", targetPrice: nil,
                           thesis: "Source thesis", invalidation: nil, publishedAt: now.addingTimeInterval(-age), evidenceURL: nil)
    }

    private func movement(_ ticker: String, age: TimeInterval = 100, market: String = "xyz:NVDA") -> SmartMoneyMovement {
        SmartMoneyMovement(id: UUID(), ticker: ticker, companyName: ticker, accountId: "author", accountLabel: "author",
                           accountScore: 80, market: market, action: .reduced, direction: .bullish,
                           notionalBefore: 1000, notionalAfter: 800, notionalChange: -200, leverage: nil,
                           observedAt: now.addingTimeInterval(-age), evidenceURL: nil)
    }
}
