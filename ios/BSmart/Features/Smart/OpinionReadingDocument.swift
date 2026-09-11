import Foundation
import NaturalLanguage

struct OpinionReadingDocument {
    struct Block: Identifiable {
        let id: Int
        let text: String
        let isHeading: Bool
        let emphasis: [NSRange]
    }

    let originalText: String
    let blocks: [Block]

    init(text: String, evidence: String? = nil) {
        originalText = text
        let source = text as NSString
        let highlight = Self.evidenceRange(evidence, in: text)
        var ranges: [Range<String.Index>] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byParagraphs) { _, range, _, _ in
            let paragraph = String(text[range])
            guard !paragraph.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let cjkCount = paragraph.unicodeScalars.filter { (0x2E80...0x9FFF).contains($0.value) }.count
            let limit = cjkCount > paragraph.count / 4 ? 220 : 480
            guard paragraph.count > limit else {
                ranges.append(range)
                return
            }
            // Split dense paragraphs only at language-aware sentence boundaries.
            // The stored text and the copy action retain the complete source verbatim.
            var start = range.lowerBound
            text.enumerateSubstrings(in: range, options: .bySentences) { _, sentence, _, _ in
                if text[start..<sentence.upperBound].count >= limit {
                    ranges.append(start..<sentence.upperBound)
                    start = sentence.upperBound
                }
            }
            if start < range.upperBound { ranges.append(start..<range.upperBound) }
        }
        blocks = ranges.enumerated().compactMap { index, range in
            let nsRange = NSRange(range, in: text)
            let value = source.substring(with: nsRange)
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let intersection = highlight.map { NSIntersectionRange(nsRange, $0) }
            let emphasis = intersection.flatMap { overlap -> NSRange? in
                guard overlap.length > 0 else { return nil }
                return NSRange(location: overlap.location - nsRange.location, length: overlap.length)
            }
            return Block(id: index, text: value, isHeading: Self.isHeading(value),
                         emphasis: emphasis.map { [$0] } ?? [])
        }
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
