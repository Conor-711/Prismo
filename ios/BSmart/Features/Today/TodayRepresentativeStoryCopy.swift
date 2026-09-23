import Foundation

enum TodayRepresentativeStoryCopy {
    static func text(_ story: TodayRepresentativeStory) -> String {
        if BSmartLocalization.isSimplifiedChinese, let copy = story.bundledChineseCopy { return copy }
        if !BSmartLocalization.isSimplifiedChinese, let copy = story.bundledEnglishCopy { return copy }
        let first = story.anchor
        let remaining = Array(story.earliestCalls.dropFirst())
        let before = remaining.filter { $0.day < story.peak.day }
        let after = remaining.filter { $0.day > story.peak.day }
        let sameDay = remaining.filter { $0.day == story.peak.day }
        var sentences = ["The author was bullish on %@ at %@."
            .bSmartLocalized(story.ticker, price(first.price))]
        if !before.isEmpty { sentences.append(repeated(before, afterPeak: false, start: first.price)) }
        if story.peakChange > 0 {
            sentences.append("It later reached %@, about %@ above that first price."
                .bSmartLocalized(price(story.peak.value), percent(story.peakChange)))
        } else {
            sentences.append("The later high was %@, no higher than that first price."
                .bSmartLocalized(price(story.peak.value)))
        }
        if !sameDay.isEmpty {
            sentences.append((sameDay.count == 1
                ? "They also posted a bullish view on the day of that high."
                : "They also posted two bullish views on the day of that high.").bSmartLocalized)
        }
        if !after.isEmpty { sentences.append(repeated(after, afterPeak: true, start: story.peak.value)) }
        return sentences.joined(separator: BSmartLocalization.isSimplifiedChinese ? "" : " ")
    }

    private static func repeated(_ calls: [TodayRepresentativeStory.Call], afterPeak: Bool, start: Double) -> String {
        let prices = calls.map { price($0.price) }
        if calls.count == 1 {
            return (afterPeak ? "Later, at %@, they posted another bullish view." : "At %@, they posted another bullish view.")
                .bSmartLocalized(prices[0])
        }
        if afterPeak && calls.allSatisfy({ $0.price < start }) {
            return "After it pulled back to %@ and %@, they posted two more bullish views.".bSmartLocalized(prices[0], prices[1])
        }
        if !afterPeak && calls[0].price > start && calls[1].price > calls[0].price {
            return "As it rose to %@ and then %@, they posted two more bullish views.".bSmartLocalized(prices[0], prices[1])
        }
        return "At %@ and %@, they posted two more bullish views.".bSmartLocalized(prices[0], prices[1])
    }

    static func day(_ day: String) -> String { day.replacingOccurrences(of: "-", with: ".") }
    static func emphasisRanges(in text: String, ticker: String) -> [Range<String.Index>] {
        let symbol = NSRegularExpression.escapedPattern(for: ticker)
        let pattern = "(?<![A-Za-z0-9])" + symbol + "(?![A-Za-z0-9])|\\$[0-9,]+(?:\\.[0-9]+)?|[+-]?[0-9,]+(?:\\.[0-9]+)?%"
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        return expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text) }
    }
    static func price(_ value: Double) -> String {
        value.formatted(.bSmartDollars.precision(.fractionLength(0...2)))
    }
    static func chartPrice(_ value: Double) -> String {
        value.formatted(.bSmartDollars.precision(.fractionLength(0)))
    }
    static func percent(_ value: Double) -> String {
        value.formatted(.number.locale(Locale(identifier: "en_US")).precision(.fractionLength(0))) + "%"
    }
}
