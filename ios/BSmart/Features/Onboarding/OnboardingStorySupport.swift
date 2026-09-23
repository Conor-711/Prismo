import Foundation

enum OnboardingFeaturedStory {
    static let authorID = "1940360837547565056"
    static let story = TodayRepresentativeStoryBundle.bundled?.stories.first {
        $0.account.id == authorID && $0.ticker == "AAOI"
    }

    static let latestViewDay = "2026.08.24"
    static let latestViewTitle = "Financing dilution adds pressure, but AAOI demand remains strong"
    static let latestViewQuote = "I don't need to support every company decision to stay bullish."
}

struct OnboardingTradeDraft: Equatable {
    let marginText: String
    let leverage: Int

    static let sample = OnboardingTradeDraft(marginText: "100", leverage: 1)

    var margin: Double {
        max(0, Double(marginText) ?? 0)
    }

    var notional: Double {
        margin * Double(max(1, leverage))
    }

    var isValid: Bool {
        margin > 0 && margin.isFinite && (1...3).contains(leverage)
    }
}

enum OnboardingMoney {
    static func string(_ value: Double, maximumFractionDigits: Int = 2) -> String {
        "$" + value.formatted(
            .number
                .grouping(.automatic)
                .precision(.fractionLength(0...maximumFractionDigits))
        )
    }
}
