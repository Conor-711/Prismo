import XCTest
@testable import BSmart

final class OpinionReadingDocumentTests: XCTestCase {
    private func visibleContent(_ text: String) -> String {
        text.filter { !$0.isWhitespace }
    }

    func testParagraphsPreserveSourceHeadingsListsNumbersAndURLs() {
        let text = "MARGINS:\nRevenue grew 25.5%.\n\n1. Demand improved.\n2. Execution is NOT proven.\r\n\r\nSource: https://example.com/news?q=1.5\n价格 $125.50，涨幅 +5%。"
        let document = OpinionReadingDocument(text: text)
        XCTAssertEqual(document.originalText, text)
        XCTAssertEqual(visibleContent(document.blocks.map(\.text).joined()), visibleContent(text))
        XCTAssertTrue(document.blocks.first!.isHeading)
        XCTAssertTrue(document.blocks.contains { $0.text.contains("NOT proven") })
        XCTAssertTrue(document.blocks.contains { $0.text.contains("https://example.com/news?q=1.5") })
    }

    func testDenseEnglishAndChineseParagraphsBreakOnlyAtSentencesWithoutDroppingText() {
        for sentence in [
            "Revenue increased, but management has not proven that margins can improve. ",
            "公司收入增长，但管理层仍未证明利润率可以持续改善。"
        ] {
            let text = String(repeating: sentence, count: 35)
            let document = OpinionReadingDocument(text: text)
            XCTAssertGreaterThan(document.blocks.count, 1)
            XCTAssertEqual(visibleContent(document.blocks.map(\.text).joined()), visibleContent(text))
            XCTAssertEqual(document.originalText, text)
            for block in document.blocks {
                XCTAssertTrue(block.text.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(sentence.contains("。") ? "。" : "."))
            }
        }
    }

    func testLongTranscriptUsesShortReadingBlocksAndRetainsSourceParagraphs() {
        let chinese = String(repeating: "价格正在接近关键支撑位。若无法守住该位置，短期趋势仍有风险。", count: 5)
        let english = String(repeating: "The stock is near support. A break below it remains a risk. ", count: 8)
        let text = chinese + "\n\n" + english
        let document = OpinionReadingDocument(text: text)

        XCTAssertEqual(document.originalText, text)
        XCTAssertEqual(visibleContent(document.blocks.map(\.text).joined()), visibleContent(text))
        XCTAssertGreaterThan(document.blocks.count, 4)
        XCTAssertEqual(document.blocks.filter(\.startsNewParagraph).count, 2)
        XCTAssertTrue(document.blocks.allSatisfy { $0.text.count <= 220 })
        XCTAssertTrue(document.blocks.filter { $0.text.contains("价格") }.allSatisfy { $0.text.count <= 88 })
    }

    func testEvidenceHighlightPreservesConditionsAndMatchesAcrossWhitespace() {
        let text = "Prices may rise if demand holds.\n\nThey may FALL if it does not."
        let document = OpinionReadingDocument(text: text, evidence: "Prices may rise if demand holds. They may FALL if it does not.")
        let highlighted = document.blocks.flatMap { block in
            block.emphasis.map { (block.text as NSString).substring(with: $0) }
        }.joined()
        XCTAssertEqual(visibleContent(highlighted), visibleContent(text))
        XCTAssertTrue(highlighted.contains("if demand holds"))
        XCTAssertTrue(highlighted.contains("may FALL"))
        XCTAssertTrue(OpinionReadingDocument(text: text, evidence: "Prices will rise.").blocks.allSatisfy { $0.emphasis.isEmpty })
    }

    func testRepeatedTextAndEmojiHaveStableDistinctBlocksAndValidHighlightRanges() {
        let text = "📈 $NVDA +5%.\n\n📈 $NVDA +5%.\n\nExecution remains uncertain."
        let document = OpinionReadingDocument(text: text, evidence: "📈 $NVDA +5%.")
        XCTAssertEqual(Set(document.blocks.map(\.id)).count, document.blocks.count)
        XCTAssertEqual(document.blocks.flatMap(\.emphasis).count, 1)
        XCTAssertEqual((document.blocks[0].text as NSString).substring(with: document.blocks[0].emphasis[0]), "📈 $NVDA +5%.")
        XCTAssertTrue(OpinionReadingDocument(text: " \n\n ").blocks.isEmpty)
    }

    func testChineseTranscriptEmphasizesTickersPricesAndSignalsWithoutChangingText() {
        let text = "NVDA突破关键阻力位214，目标价上调至236。SPY仍然看涨，21小时均线只是参考；我会在$125.50附近止损。"
        let document = OpinionReadingDocument(text: text, ticker: "NVDA")
        let marked = document.blocks.flatMap { block in
            block.inlineEmphasis.map { (block.text as NSString).substring(with: $0) }
        }
        XCTAssertEqual(document.originalText, text)
        XCTAssertEqual(visibleContent(document.blocks.map(\.text).joined()), visibleContent(text))
        for term in ["NVDA", "214", "236", "SPY", "$125.50"] {
            XCTAssertTrue(marked.contains(term), "Missing emphasis for \(term)")
        }
        XCTAssertFalse(marked.contains("21"))
        XCTAssertLessThanOrEqual(marked.count, 7)
    }

    func testEnglishTranscriptEmphasizesRealSymbolsAndAmountsNotOrdinaryWordsOrDates() {
        let text = "NVDA and $TEST remain bullish near $125.50. My price target is 150, with a stop loss at 110. The video was posted on 2026-09-23 at 10:30."
        let document = OpinionReadingDocument(text: text, ticker: "NVDA")
        let marked = document.blocks.flatMap { block in
            block.inlineEmphasis.map { (block.text as NSString).substring(with: $0) }
        }
        for term in ["NVDA", "$TEST", "$125.50", "150", "110", "bullish"] {
            XCTAssertTrue(marked.contains(term), "Missing emphasis for \(term)")
        }
        XCTAssertFalse(marked.contains("2026"))
        XCTAssertFalse(marked.contains("10"))
        XCTAssertEqual(visibleContent(document.blocks.map(\.text).joined()), visibleContent(text))
    }

    func testPriceContextDoesNotTurnMovingAverageOrURLIntoPrice() {
        let text = "支撑位21小时均线，目标价为214。来源：https://example.com/SPY，今天关注AAPL和QQQ。"
        let document = OpinionReadingDocument(text: text, ticker: "AAPL")
        let marked = document.blocks.flatMap { block in
            block.inlineEmphasis.map { (block.text as NSString).substring(with: $0) }
        }
        XCTAssertTrue(marked.contains("214"))
        XCTAssertTrue(marked.contains("AAPL"))
        XCTAssertTrue(marked.contains("QQQ"))
        XCTAssertFalse(marked.contains("21"))
        XCTAssertFalse(marked.contains("SPY"))
    }

    func testExistingLongPostsKeepEveryWordAndTheUnmodifiedCopyText() async throws {
        let updates = try await BundleBSmartAPIClient().fetchSmartAccountUpdates()
        let longPosts = updates.compactMap(\.originalText).filter { $0.count > 500 }
        XCTAssertFalse(longPosts.isEmpty)
        for original in longPosts {
            let document = OpinionReadingDocument(text: original)
            XCTAssertEqual(document.originalText, original)
            XCTAssertEqual(visibleContent(document.blocks.map(\.text).joined()), visibleContent(original))
        }
    }

    func testTranslationsAreSeparateFromSummaryAndOriginalAndRespectLocale() async throws {
        let updates = try await BundleBSmartAPIClient().fetchSmartAccountUpdates()
        var update = try XCTUnwrap(updates.first)
        update.originalText = "Revenue increased, but execution remains uncertain."
        update.translatedTextZH = "收入增长，但执行情况仍有不确定性。"
        update.translatedTextEN = update.originalText
        update.activityTitleZH = "收入改善，执行仍待验证"
        let chinese = OpinionReadingContent(update: update, chinese: true)
        XCTAssertEqual(chinese.original, update.originalText)
        XCTAssertEqual(chinese.translation, update.translatedTextZH)
        XCTAssertEqual(chinese.summary, update.activityTitleZH)
        XCTAssertNil(OpinionReadingContent(update: update, chinese: false).translation)
        update.translatedText = update.translatedTextZH
        update.translatedTextZH = nil
        update.translatedTextEN = nil
        XCTAssertEqual(OpinionReadingContent(update: update, chinese: true).translation, update.translatedText)
        XCTAssertNil(OpinionReadingContent(update: update, chinese: false).translation)
        update.originalText = nil
        XCTAssertNil(OpinionReadingContent(update: update, chinese: true).original)
        XCTAssertNotNil(OpinionReadingContent(update: update, chinese: true).translation)
        update.translatedText = "  "
        XCTAssertNil(OpinionReadingContent(update: update, chinese: true).translation)
    }
}
