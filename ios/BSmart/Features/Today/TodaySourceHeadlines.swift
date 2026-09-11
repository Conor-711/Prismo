import SwiftUI

/// Presentation of independent source summaries; never synthesizes a shared thesis.
struct TodaySourceHeadline: Identifiable {
    let id: UUID
    let text: String
    let sourceName: String
    let date: Date

    static func account(_ update: SmartAccountUpdate) -> Self {
        let candidates = BSmartLocalization.isSimplifiedChinese
            ? [update.activityTitleZH, update.translatedTextZH, update.activityTitleEN, update.thesis]
            : [update.activityTitleEN, update.activityTitle, update.thesis]
        // Old exports can have a qualifier cut off mid-sentence. Prefer complete
        // source text, including another language, over a misleading fragment.
        let values = candidates.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let value = values.first { !$0.contains("…") && !$0.hasSuffix("...") }
            ?? update.thesis
        return Self(id: update.id, text: clean(value, ticker: update.ticker),
                    sourceName: update.authorName, date: update.publishedAt)
    }

    static func clean(_ value: String, ticker: String) -> String {
        let symbol = NSRegularExpression.escapedPattern(for: ticker)
        let patterns = [
            "^(?:加强|结束)\\s*\(symbol)\\s*(?:判断|观点)[：:]\\s*",
            "^\(symbol)\\s*(?:观点反转|观点失效|最新判断)[：:]\\s*",
            "^(?:Strengthens|Closes)\\s+\(symbol)\\s+view:\\s*",
            "^\(symbol)\\s+view (?:reversed|invalidated):\\s*",
            "^\\$?\(symbol)[：:]\\s*",
            "^(?:该)?(?:作者|博主)[：:，,\\s]*",
            "^(?:the\\s+)?(?:author|creator)\\s+"
        ]
        var text = value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        for pattern in patterns {
            text = text.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        // Remove reporting boilerplate and extractor classifications, not the
        // source's investment conditions, prices, intent or time horizon.
        for prefix in ["在投资组合更新中明确表示", "在投资组合更新中表示", "直接声明", "明确表示", "表示"] {
            if text.hasPrefix(prefix) { text = String(text.dropFirst(prefix.count)) }
        }
        for annotation in ["，属于明确的减仓行动，方向偏空", "，属于看涨持仓声明"] {
            text = text.replacingOccurrences(of: annotation, with: "")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct TodaySourceHeadlineList: View {
    let label: String
    let headlines: [TodaySourceHeadline]
    var foreground: Color = BSmartColor.primaryText

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label.bSmartLocalized)
                .font(.caption2.weight(.bold))
                .foregroundStyle(foreground.opacity(0.65))
            ForEach(headlines) { headline in
                VStack(alignment: .leading, spacing: 5) {
                    Text(headline.text)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        Text(headline.sourceName)
                        Text(headline.date.bSmartRelativeTimestamp)
                    }
                    .font(.caption2)
                    .foregroundStyle(foreground.opacity(0.65))
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
