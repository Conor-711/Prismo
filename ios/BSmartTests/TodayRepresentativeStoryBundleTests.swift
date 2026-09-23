import XCTest
@testable import BSmart

final class TodayRepresentativeStoryBundleTests: XCTestCase {
    func testPreparedChartDomainsAndMarkersMatchEveryBundledStory() throws {
        let snapshot = try XCTUnwrap(TodayRepresentativeStoryBundle.bundled)
        for story in snapshot.stories {
            let data = try XCTUnwrap(TodayRepresentativeChartData(story: story))
            XCTAssertEqual(data.calls.map(\.id), story.earliestCalls.map(\.id))
            XCTAssertEqual(data.timeDomain, story.prices.first!.time...story.prices.last!.time)
            for value in story.prices.map(\.value) + data.calls.map(\.price) + [story.peak.value] {
                XCTAssertTrue(data.priceDomain.contains(value))
            }
            let size = CGSize(width: 320, height: 128)
            XCTAssertEqual(data.point(time: data.timeDomain.lowerBound, value: data.priceDomain.upperBound, in: size),
                           CGPoint(x: 14, y: 0))
            XCTAssertEqual(data.point(time: data.timeDomain.upperBound, value: data.priceDomain.lowerBound, in: size),
                           CGPoint(x: 306, y: 128))
            XCTAssertEqual(data.callPoints(in: size).count, data.calls.count)
            XCTAssertTrue(data.callPoints(in: size).allSatisfy { $0.x.isFinite && $0.y.isFinite })
        }
    }

    func testChartRejectsEmptyOrMalformedDecodedDataWithoutIndexing() throws {
        let story = try XCTUnwrap(TodayRepresentativeStoryBundle.bundled?.stories.first)
        let encoded = try PropertyListEncoder().encode(story)
        let original = try XCTUnwrap(PropertyListSerialization.propertyList(from: encoded, format: nil) as? [String: Any])
        for field in ["prices", "calls"] {
            var broken = original
            broken[field] = []
            let data = try PropertyListSerialization.data(fromPropertyList: broken, format: .binary, options: 0)
            XCTAssertNil(TodayRepresentativeChartData(story: try PropertyListDecoder().decode(TodayRepresentativeStory.self, from: data)))
        }
    }

    func testExportSnapshot() throws {
        guard let path = ProcessInfo.processInfo.environment["BSMART_STORY_EXPORT_PATH"] else {
            throw XCTSkip("Run the explicit representative-story export workflow to regenerate the bundle.")
        }
        let accounts: [SmartAccountProfile] = try fixture("smart-accounts")
        let evidence: [SmartAccountUpdate] = try fixture("smart-account-evidence")
        let updates: [SmartAccountUpdate] = try fixture("smart-account-updates")
        let grouped = Dictionary(grouping: evidence + updates) {
            TodayInvestorDiscovery.identity($0.authorId, platform: $0.platform)
        }
        let previousLanguage = BSmartLocalization.language
        defer { BSmartLocalization.configure(previousLanguage) }
        let now = Date()
        var stories: [TodayRepresentativeStory] = []
        for account in accounts {
            let records = grouped[TodayInvestorDiscovery.identity(account.id, platform: account.platform)] ?? []
            guard var story = TodayRepresentativeStory(account: account, intro: account.representativeWork,
                                                       evidence: records, now: now) else { continue }
            BSmartLocalization.configure(.simplifiedChinese)
            story.bundledChineseCopy = TodayRepresentativeStoryCopy.text(story)
            BSmartLocalization.configure(.english)
            story.bundledEnglishCopy = TodayRepresentativeStoryCopy.text(story)
            stories.append(story)
        }
        let snapshot = TodayRepresentativeStoryBundle(formatVersion: TodayRepresentativeStoryBundle.version,
            generatedAt: now, introductions: accounts.compactMap(\.representativeWork), stories: stories)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(snapshot)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        print("REPRESENTATIVE_STORY_EXPORT introductions=\(snapshot.introductions.count) stories=\(stories.count) bytes=\(data.count)")
        XCTAssertGreaterThan(stories.count, 200)
    }

    func testBundledStoriesLoadWithoutNetworkAndContainNeutralBilingualCopy() throws {
        let snapshot = try XCTUnwrap(TodayRepresentativeStoryBundle.bundled)
        let accounts: [SmartAccountProfile] = try fixture("smart-accounts")
        XCTAssertEqual(snapshot.introductions.count, accounts.filter { $0.representativeWork != nil }.count)
        XCTAssertGreaterThan(snapshot.stories.count, 200)
        for story in snapshot.stories {
            XCTAssertLessThanOrEqual(story.earliestCalls.count, 3)
            let chinese = try XCTUnwrap(story.bundledChineseCopy)
            let english = try XCTUnwrap(story.bundledEnglishCopy)
            XCTAssertFalse(chinese.contains("就"), chinese)
            XCTAssertTrue(chinese.contains("作者"), chinese)
            XCTAssertTrue(english.lowercased().contains("the author"), english)
            XCTAssertFalse(chinese.contains(TodayRepresentativeStoryCopy.day(story.anchor.day)))
            XCTAssertFalse(english.contains(TodayRepresentativeStoryCopy.day(story.anchor.day)))
            XCTAssertTrue(story.calls.allSatisfy { $0.original == nil })
        }
        let serenity = try XCTUnwrap(accounts.first { $0.handle.lowercased() == "@aleabitoreddit" })
        XCTAssertEqual(snapshot.story(for: serenity)?.ticker, "AAOI")
    }

    func testEmphasisIncludesTickerMoneyAndPercentOnly() {
        let text = "2025.12.05，作者在 $237.22 看多 MU，最高到 $1,255，涨幅 429%。"
        let values = TodayRepresentativeStoryCopy.emphasisRanges(in: text, ticker: "MU").map { String(text[$0]) }
        XCTAssertEqual(values, ["$237.22", "MU", "$1,255", "429%"])
    }

    @MainActor
    func testOpinionDestinationsMatchSourcesInsteadOfRepresentativeIDs() throws {
        let snapshot = try XCTUnwrap(TodayRepresentativeStoryBundle.bundled)
        let evidence: [SmartAccountUpdate] = try fixture("smart-account-evidence")
        let updates: [SmartAccountUpdate] = try fixture("smart-account-updates")
        let grouped = Dictionary(grouping: evidence + updates) {
            TodayInvestorDiscovery.identity($0.authorId, platform: $0.platform)
        }
        var fullCount = 0, summaryCount = 0
        for story in snapshot.stories {
            let records = grouped[TodayInvestorDiscovery.identity(story.account.id, platform: story.account.platform)] ?? []
            for call in story.earliestCalls {
                let result = TodayRepresentativeOpinionDestination.resolve(story: story, call: call, evidence: records)
                XCTAssertEqual(result.ticker, story.ticker)
                XCTAssertEqual(result.publishedAt, call.publishedAt)
                XCTAssertEqual(TodayRepresentativeStory.sourceKey(result.sourceURL ?? result.evidenceURL),
                               TodayRepresentativeStory.sourceKey(call.sourceURL))
                if let full = records.first(where: {
                    $0.ticker == story.ticker && TodayRepresentativeStory.sourceKey($0.sourceURL ?? $0.evidenceURL)
                        == TodayRepresentativeStory.sourceKey(call.sourceURL)
                }) {
                    XCTAssertEqual(result, full)
                    fullCount += 1
                } else {
                    XCTAssertNil(result.originalText)
                    XCTAssertNil(result.translatedText)
                    XCTAssertNil(result.settlement)
                    XCTAssertEqual(result.thesis, call.summary ?? "")
                    XCTAssertEqual(result.horizon, call.horizon ?? "unknown")
                    summaryCount += 1
                }
            }
        }
        XCTAssertGreaterThan(fullCount, 0)
        XCTAssertGreaterThan(summaryCount, 0)
    }

    func testCompactAnnotationsDoNotCoverTheThreeTapTargets() throws {
        let snapshot = try XCTUnwrap(TodayRepresentativeStoryBundle.bundled)
        for story in snapshot.stories {
            for width in [280.0, 320, 390] {
                let size = CGSize(width: width, height: 128)
                let values = story.prices.map(\.value) + story.earliestCalls.map(\.price) + [story.peak.value]
                let low = values.min()!, high = values.max()!
                let pad = max(high - low, high * 0.1) * 0.25
                let start = story.prices.first!.time, end = story.prices.last!.time
                func point(_ day: String, _ price: Double) -> CGPoint {
                    let time = BSmartChartCandle.day(day)!
                    return CGPoint(x: 14 + (width - 28) * time.timeIntervalSince(start) / end.timeIntervalSince(start),
                        y: 128 * (1 - (price - low + pad) / (high - low + 2 * pad)))
                }
                let anchors = story.earliestCalls.map { point($0.day, $0.price) }
                let labels = TodayRepresentativeStoryAnnotations(first: anchors[0],
                    peak: point(story.peak.day, story.peak.value), size: size, scale: 1)
                let positions = BSmartChartMarkerLayout.positions(anchors: anchors, size: size,
                    avoiding: [labels.first, labels.peak])
                for position in positions {
                    let rect = CGRect(x: position.x - 22, y: position.y - 22, width: 44, height: 44)
                    XCTAssertFalse(rect.intersects(labels.first), "\(story.account.id) / \(story.ticker) / \(width)")
                    XCTAssertFalse(rect.intersects(labels.peak), "\(story.account.id) / \(story.ticker) / \(width)")
                }
            }
        }
    }

    private func fixture<T: Decodable>(_ name: String) throws -> T {
        let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "json"))
        return try BSmartJSONCoding.makeDecoder().decode(T.self, from: Data(contentsOf: url))
    }
}
