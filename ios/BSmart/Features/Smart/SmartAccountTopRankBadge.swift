import SwiftUI

enum SmartAccountRankPresentation {
    static func topPercent(_ account: SmartAccountProfile) -> Int? {
        guard let value = account.platformPercentile,
              value.isFinite, (0...1).contains(value) else { return nil }
        return max(1, Int(ceil(value * 100)))
    }

    static func label(_ account: SmartAccountProfile) -> String? {
        if let percent = topPercent(account) { return "TOP \(percent)%" }
        guard account.resolvedPlatformRank > 0 else { return nil }
        return "#\(account.resolvedPlatformRank)"
    }
}

struct SmartAccountTopRankBadge: View {
    let account: SmartAccountProfile

    var body: some View {
        if let label = SmartAccountRankPresentation.label(account) {
            Text(label)
                .font(.headline.weight(.bold)).monospacedDigit()
                .foregroundStyle(BSmartColor.onAccent)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(BSmartColor.brand, in: RoundedRectangle(cornerRadius: 6))
                .fixedSize()
                .accessibilityLabel("\(account.platform) · \(label)")
                .accessibilityIdentifier("smart.account.top-rank")
        }
    }
}
