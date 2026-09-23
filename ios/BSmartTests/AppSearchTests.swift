import XCTest
@testable import BSmart

final class AppSearchTests: XCTestCase {
    func testExactTickerFirstAndCategoriesStayInRequestedOrder() {
        let author = AppSearchItem.author(SmartAccountProfile(id: "btc-research", name: "BTC Research",
            handle: "@btc", platform: "X", score: 100, scoreChange: 0, specialty: "Crypto", horizon: "20D", recentTicker: "BTC"))
        let user = AppSearchItem.user(.init(id: UUID(), nickname: "BTC Trader", avatarURL: nil, handle: "btc_trader"))
        let older = opinion("BTC", age: 100), newer = opinion("BTC", age: 1)
        let index = AppSearchIndex(items: [user, author, older, ticker("WBTC"), newer, ticker("BTC"), older])
        let found = index.search("btc")
        XCTAssertEqual(found.first?.id, "ticker:BTC")
        XCTAssertEqual(found.map(\.category), [.tickers, .tickers, .opinions, .opinions, .authors, .users])
        XCTAssertEqual(Array(found[2...3]).map(\.id), [newer.id, older.id])
        XCTAssertEqual(Set(found.map(\.id)).count, found.count)
    }

    func testAliasesNormalizationAndMultipleTerms() {
        let index = AppSearchIndex(items: [ticker("BTC"), ticker("ETH"), opinion("BTC")])
        for query in ["  $BTC  ", "ＢＴＣ", "Bitcoin", "比特币"] {
            XCTAssertEqual(index.search(query).first?.id, "ticker:BTC", query)
        }
        XCTAssertEqual(index.search("btc momentum").map(\.category), [.opinions])
        XCTAssertTrue(index.search("btc impossibleword").isEmpty)
        XCTAssertTrue(index.search("unmatched-query").isEmpty)
        let person = FeedPublicProfile(id: UUID(), nickname: "René", avatarURL: nil, handle: "rene_btc")
        let people = AppSearchIndex(items: [.user(person)])
        XCTAssertEqual(people.search("@RENE_BTC").count, 1)
        XCTAssertEqual(people.search("rene").count, 1)
    }

    func testMissingQuoteRemainsMissingAndOverviewIsDeduplicated() {
        let view = opinion("BTC")
        let data = AppSearchOverviewData(items: [ticker("ETH"), ticker("BTC"), view, view], trendingSymbols: ["BTC"])
        XCTAssertEqual(data.tickers.first?.id, "ticker:BTC")
        XCTAssertEqual(data.opinions.count, 1)
        guard case .ticker(let value) = data.tickers[0] else { return XCTFail("Expected asset") }
        XCTAssertNil(value.price)
    }

    func testTickerSymbolOutranksAnotherAssetsMatchingName() {
        let index = AppSearchIndex(items: [.ticker(.init(symbol: "AAA", companyName: "BTC")), ticker("BTC")])
        XCTAssertEqual(index.search("BTC").map(\.id), ["ticker:BTC", "ticker:AAA"])
    }

    func testInvestorRankUsesPublishedPercentileWithoutInventingMissingRanks() {
        var author = SmartAccountProfile(id: "ranked", name: "Ranked investor", handle: "@ranked", platform: "X",
            score: 100, scoreChange: 0, specialty: "Tech", horizon: "20D", recentTicker: "NVDA")
        XCTAssertNil(AppSearchItem.author(author).investorRanking)
        author.platformPercentile = 0.08
        XCTAssertEqual(AppSearchItem.author(author).investorRanking, "Top 8%")
        author.platformPercentile = 0
        XCTAssertEqual(AppSearchItem.author(author).investorRanking, "Top 1%")
        author.platformPercentile = .nan
        XCTAssertNil(AppSearchItem.author(author).investorRanking)
        author.rank = 3
        XCTAssertEqual(AppSearchItem.author(author).investorRanking, "#3")
        author.platformPercentile = 5
        XCTAssertEqual(AppSearchItem.author(author).investorRanking, "#3")
        XCTAssertNil(ticker("BTC").investorRanking)
    }

    @MainActor func testLateSearchResponseCannotOverwriteNewQuery() async {
        let store = AppSearchStore()
        await store.replaceIndex(items: [ticker("BTC"), ticker("ETH")])
        var release: CheckedContinuation<PublicProfileSearchPage, Error>?
        let first = Task {
            await store.search("BTC", fetchUsers: { _, _ in
                try await withCheckedThrowingContinuation { release = $0 }
            }, debounce: false)
        }
        while release == nil { await Task.yield() }
        await store.search("ETH", fetchUsers: nil, debounce: false)
        release?.resume(returning: .init(items: [person("Old")], nextOffset: nil))
        await first.value
        XCTAssertEqual(store.results.map(\.id), ["ticker:ETH"])
        XCTAssertTrue(store.users.isEmpty)
        XCTAssertFalse(store.usersLoading)
    }

    @MainActor func testCancelledSearchAndAccountSwitchDiscardResponses() async {
        let store = AppSearchStore()
        await store.replaceIndex(items: [ticker("BTC")])
        let cancelled = Task { await store.search("BTC", fetchUsers: nil) }
        cancelled.cancel()
        await cancelled.value
        XCTAssertTrue(store.results.isEmpty)
        var release: CheckedContinuation<PublicProfileSearchPage, Error>?
        let pending = Task {
            await store.search("BTC", fetchUsers: { _, _ in
                try await withCheckedThrowingContinuation { release = $0 }
            }, debounce: false)
        }
        while release == nil { await Task.yield() }
        store.setAccount(UUID())
        release?.resume(returning: .init(items: [person("Previous")], nextOffset: nil))
        await pending.value
        XCTAssertTrue(store.users.isEmpty && store.results.isEmpty)
    }

    @MainActor func testUserFailureDoesNotEraseAssetResultsAndRetryWorks() async {
        let store = AppSearchStore()
        await store.replaceIndex(items: [ticker("BTC")])
        await store.search("BTC", fetchUsers: { _, _ in throw URLError(.notConnectedToInternet) }, debounce: false)
        XCTAssertEqual(store.results.first?.id, "ticker:BTC")
        XCTAssertTrue(store.usersFailed)
        let user = person("BTC Trader")
        await store.retryUsers { query, offset in
            XCTAssertEqual(query, "BTC"); XCTAssertEqual(offset, 0)
            return .init(items: [user], nextOffset: nil)
        }
        XCTAssertFalse(store.usersFailed)
        XCTAssertEqual(store.users.map(\.id), [user.id])
    }

    @MainActor func testPagingAndHistoryAreBoundedAndAccountScoped() async {
        let suite = "search-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppSearchStore(defaults: defaults)
        let owner = UUID()
        store.setAccount(owner)
        for i in 0..<10 { store.remember("query\(i)") }
        store.remember("QUERY9")
        XCTAssertEqual(store.recentQueries.count, 8)
        XCTAssertEqual(store.recentQueries.first, "QUERY9")
        store.setAccount(UUID())
        XCTAssertTrue(store.recentQueries.isEmpty)
        store.setAccount(owner)
        XCTAssertEqual(store.recentQueries.count, 8)
        store.clearHistory()
        store.setAccount(owner)
        XCTAssertTrue(store.recentQueries.isEmpty)
        let first = person("First"), second = person("Second")
        await store.search("", fetchUsers: { _, _ in .init(items: [first], nextOffset: 1) }, debounce: false)
        await store.moreUsers { _, offset in
            XCTAssertEqual(offset, 1)
            return .init(items: [first, second], nextOffset: nil)
        }
        XCTAssertEqual(store.users.map(\.id), [first.id, second.id])
        XCTAssertNil(store.nextUserOffset)
    }

    func testInvalidUserPagesAreRejected() {
        let user = person("Valid")
        XCTAssertThrowsError(try PublicProfileSearchPage(items: [user, user], nextOffset: nil).validate(offset: 0))
        XCTAssertThrowsError(try PublicProfileSearchPage(items: [user], nextOffset: 5).validate(offset: 0))
        XCTAssertThrowsError(try PublicProfileSearchPage(items: [], nextOffset: 1).validate(offset: 0))
        XCTAssertThrowsError(try PublicProfileSearchPage(items: [], nextOffset: nil).validate(offset: -1))
    }

    private func person(_ name: String) -> FeedPublicProfile { .init(id: UUID(), nickname: name, avatarURL: nil) }
    private func ticker(_ value: String) -> AppSearchItem { .ticker(.init(symbol: value, companyName: value)) }
    private func opinion(_ ticker: String, age: TimeInterval = 1) -> AppSearchItem {
        .opinion(.init(id: UUID(), ticker: ticker, companyName: ticker, authorId: "author", authorName: "Researcher",
            platform: "X", score: 120, platformPercentile: 0.1, direction: .bullish, lifecycle: .new, horizon: "20D",
            targetPrice: nil, thesis: "Strong momentum", invalidation: nil,
            publishedAt: Date(timeIntervalSince1970: 1700000000 - age), evidenceURL: nil))
    }
}
