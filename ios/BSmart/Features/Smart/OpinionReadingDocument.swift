import Foundation
import NaturalLanguage

struct OpinionReadingDocument {
    struct Block: Identifiable {
        let id: Int
        let text: String
        let isHeading: Bool
        let startsNewParagraph: Bool
        let emphasis: [NSRange]
        let inlineEmphasis: [NSRange]
    }

    let originalText: String
    let blocks: [Block]

    init(text: String, evidence: String? = nil, ticker: String? = nil) {
        originalText = text
        let source = text as NSString
        let highlight = Self.evidenceRange(evidence, in: text)
        var ranges: [(range: Range<String.Index>, paragraphID: Int)] = []
        var paragraphID = 0
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byParagraphs) { _, range, _, _ in
            let currentParagraph = paragraphID
            paragraphID += 1
            let paragraph = String(text[range])
            guard !paragraph.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let cjkCount = paragraph.unicodeScalars.filter { (0x2E80...0x9FFF).contains($0.value) }.count
            let limit = cjkCount > paragraph.count / 4 ? 88 : 220
            guard paragraph.count > limit else {
                ranges.append((range, currentParagraph))
                return
            }
            // Preserve every character while giving long transcripts shorter reading pauses.
            var start = range.lowerBound
            text.enumerateSubstrings(in: range, options: .bySentences) { _, sentence, _, _ in
                if text[start..<sentence.upperBound].count > limit, start < sentence.lowerBound {
                    ranges.append((start..<sentence.lowerBound, currentParagraph))
                    start = sentence.lowerBound
                }
            }
            if start < range.upperBound { ranges.append((start..<range.upperBound, currentParagraph)) }
        }
        blocks = ranges.enumerated().compactMap { index, item in
            let range = item.range
            let nsRange = NSRange(range, in: text)
            let value = source.substring(with: nsRange)
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let intersection = highlight.map { NSIntersectionRange(nsRange, $0) }
            let emphasis = intersection.flatMap { overlap -> NSRange? in
                guard overlap.length > 0 else { return nil }
                return NSRange(location: overlap.location - nsRange.location, length: overlap.length)
            }
            return Block(id: index, text: value, isHeading: Self.isHeading(value),
                         startsNewParagraph: index == 0 || item.paragraphID != ranges[index - 1].paragraphID,
                         emphasis: emphasis.map { [$0] } ?? [],
                         inlineEmphasis: Self.inlineEmphasis(in: value, ticker: ticker))
        }
    }

    private static let tickerPattern = try! NSRegularExpression(
        pattern: "(?<![A-Za-z0-9/.#@])\\$?[A-Za-z][A-Za-z0-9]{0,7}(?![A-Za-z0-9])"
    )
    private static let moneyPattern = try! NSRegularExpression(
        pattern: "(?<![A-Za-z0-9/])(?:US\\$|\\$|¥|￥)\\s*[+-]?\\d+(?:,\\d{3})*(?:\\.\\d+)?"
    )
    private static let contextualPricePattern = try! NSRegularExpression(
        pattern: "(?:目标价|目标位|目标为|止损价|止损位|止损设于|入场价|参考价|支撑位|阻力位|支撑区|阻力区|上调至|下调至|回调至|回落至|下探至|price target|target price|support at|resistance at|stop loss at)[^\\d\\n。。，，]{0,5}(\\d+(?:,\\d{3})*(?:\\.\\d+)?)",
        options: .caseInsensitive
    )
    private static let percentagePattern = try! NSRegularExpression(
        pattern: "(?<![A-Za-z0-9])[+-]?\\d+(?:\\.\\d+)?\\s*%"
    )
    private static let signalPattern = try! NSRegularExpression(
        pattern: "看多|看空|看涨|看跌|买入信号|卖出信号|买入机会|目标价|支撑位|阻力位|止损|止盈|风险管理|假突破|牛市陷阱|\\b(?:bullish|bearish|buy signal|sell signal|price target|stop loss|take profit|support level|resistance level|breakout|breakdown)\\b",
        options: .caseInsensitive
    )

    private static func inlineEmphasis(in text: String, ticker: String?) -> [NSRange] {
        let source = text as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        let primaryTicker = ticker?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        var result: [NSRange] = []

        func append(_ range: NSRange, limit: Int) {
            guard result.count < limit, range.location != NSNotFound, range.length > 0,
                  !result.contains(where: { NSIntersectionRange($0, range).length > 0 }) else { return }
            result.append(range)
        }

        for match in tickerPattern.matches(in: text, range: fullRange) {
            let token = source.substring(with: match.range)
            let symbol = token.hasPrefix("$") ? String(token.dropFirst()) : token
            let upper = symbol.uppercased()
            guard symbol == upper || token.hasPrefix("$") else { continue }
            guard upper == primaryTicker || token.hasPrefix("$")
                    || (upper.count >= 3 && (TickerLogoRegistry.symbols.contains(upper) || upper == "SPY")) else { continue }
            append(match.range, limit: 3)
        }
        for match in moneyPattern.matches(in: text, range: fullRange) {
            append(match.range, limit: 5)
        }
        for match in contextualPricePattern.matches(in: text, range: fullRange) {
            let range = match.range(at: 1)
            let following = source.substring(from: NSMaxRange(range))
            guard !["小时", "分钟", "日", "周", "月", "年", "%", "倍"].contains(where: following.hasPrefix) else { continue }
            append(range, limit: 5)
        }
        for match in percentagePattern.matches(in: text, range: fullRange) {
            append(match.range, limit: 6)
        }
        var signals = 0
        for match in signalPattern.matches(in: text, range: fullRange) {
            guard signals < 2 else { break }
            let count = result.count
            append(match.range, limit: 7)
            if result.count > count { signals += 1 }
        }
        return result.sorted { $0.location < $1.location }
    }

    private static func evidenceRange(_ evidence: String?, in text: String) -> NSRange? {
        guard let evidence, !evidence.isEmpty, evidence.count <= 2_000 else { return nil }
        let words = evidence.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return nil }
        let pattern = words.map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "\\s+")
        return try? NSRegularExpression(pattern: pattern)
            .firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text))?.range
    }

    private static func isHeading(_ text: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count <= 64 else { return false }
        return text.hasSuffix(":") || text.hasSuffix("：")
    }
}

struct OpinionReadingContent {
    let original: String?
    let translation: String?
    let summary: String?

    init(update: SmartAccountUpdate, chinese: Bool) {
        func nonempty(_ text: String?) -> String? {
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return text
        }
        let original = nonempty(update.originalText)
        self.original = original
        let generic = nonempty(update.translatedText).flatMap { value -> String? in
            let language = NLLanguageRecognizer.dominantLanguage(for: value)
            let matches = chinese ? language == .simplifiedChinese || language == .traditionalChinese : language == .english
            return matches ? value : nil
        }
        let candidates = [chinese ? update.translatedTextZH : update.translatedTextEN, generic]
        translation = candidates.compactMap(nonempty).first {
            $0.trimmingCharacters(in: .whitespacesAndNewlines) != original?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        summary = nonempty(chinese ? update.activityTitleZH : update.activityTitleEN)
    }
}
