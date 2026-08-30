import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case dark
    case light

    var id: String { rawValue }
    var colorScheme: ColorScheme { self == .dark ? .dark : .light }

    var displayName: String {
        switch self {
        case .dark: "Dark mode".bSmartLocalized
        case .light: "Light mode".bSmartLocalized
        }
    }

    var detail: String {
        switch self {
        case .dark: "Dark background for low-light viewing".bSmartLocalized
        case .light: "Light background for daytime viewing".bSmartLocalized
        }
    }

    var symbol: String { self == .dark ? "moon.fill" : "sun.max.fill" }
}

@MainActor
final class AppAppearanceStore: ObservableObject {
    private static let defaultsKey = "bsmart.app-appearance"

    @Published private(set) var selection: AppAppearance
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let flagIndex = arguments.firstIndex(of: "--ui-appearance"),
           arguments.indices.contains(flagIndex + 1),
           let override = AppAppearance(rawValue: arguments[flagIndex + 1]) {
            selection = override
            return
        }
        #endif
        selection = defaults.string(forKey: Self.defaultsKey)
            .flatMap(AppAppearance.init(rawValue:))
            ?? .dark
    }

    func select(_ appearance: AppAppearance) {
        guard appearance != selection else { return }
        defaults.set(appearance.rawValue, forKey: Self.defaultsKey)
        selection = appearance
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    var locale: Locale {
        switch self {
        case .system: .autoupdatingCurrent
        case .english: Locale(identifier: "en")
        case .simplifiedChinese: Locale(identifier: "zh-Hans")
        }
    }

    var displayName: String {
        switch self {
        case .system: "System".bSmartLocalized
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        }
    }

    var detail: String {
        switch self {
        case .system: "Use the device language".bSmartLocalized
        case .english: "English interface".bSmartLocalized
        case .simplifiedChinese: "Simplified Chinese interface".bSmartLocalized
        }
    }
}

@MainActor
final class AppLanguageStore: ObservableObject {
    private static let defaultsKey = "bsmart.app-language"

    @Published private(set) var selection: AppLanguage
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selection = defaults.string(forKey: Self.defaultsKey)
            .flatMap(AppLanguage.init(rawValue:))
            ?? .system
        BSmartLocalization.configure(selection)
    }

    var locale: Locale { selection.locale }

    func localized(_ key: String) -> String {
        BSmartLocalization.localized(key)
    }

    func select(_ language: AppLanguage) {
        guard language != selection else { return }
        BSmartLocalization.configure(language)
        defaults.set(language.rawValue, forKey: Self.defaultsKey)
        selection = language
    }
}

enum BSmartLocalization {
    private final class BundleToken {}

    private static let untranslatedProductTerms: Set<String> = [
        "Smart",
        "Smart Account",
        "Smart Money",
        "Mr Collie",
    ]

    private static let sourceBundle = Bundle(for: BundleToken.self)
    private static let simplifiedChineseBundle: Bundle? = {
        guard let path = sourceBundle.path(forResource: "zh-Hans", ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }()

    private(set) static var language: AppLanguage = .system

    static func configure(_ language: AppLanguage) {
        self.language = language
    }

    static func localized(_ key: String) -> String {
        guard !untranslatedProductTerms.contains(key) else { return key }

        return switch language {
        case .system:
            sourceBundle.localizedString(forKey: key, value: key, table: nil)
        case .english:
            key
        case .simplifiedChinese:
            simplifiedChineseBundle?.localizedString(forKey: key, value: key, table: nil) ?? key
        }
    }

    static var formattingLocale: Locale {
        language == .system ? .current : language.locale
    }

    static var isSimplifiedChinese: Bool {
        switch language {
        case .simplifiedChinese: true
        case .english: false
        case .system: sourceBundle.preferredLocalizations.first == "zh-Hans"
        }
    }
}

extension String {
    var bSmartLocalized: String {
        BSmartLocalization.localized(self)
    }

    func bSmartLocalized(_ arguments: CVarArg...) -> String {
        String(format: bSmartLocalized, locale: BSmartLocalization.formattingLocale, arguments: arguments)
    }
}

extension Date {
    var bSmartDataTimestamp: String {
        formatted(
            .dateTime
                .month()
                .day()
                .hour()
                .minute()
                .locale(BSmartLocalization.formattingLocale)
        )
    }

    var bSmartDigestDate: String {
        formatted(
            .dateTime
                .weekday(.wide)
                .month(.wide)
                .day()
                .locale(BSmartLocalization.formattingLocale)
        )
    }

    var bSmartCompactDate: String {
        formatted(
            .dateTime
                .month(.abbreviated)
                .day()
                .locale(BSmartLocalization.formattingLocale)
        )
    }

    var bSmartRelativeTimestamp: String {
        formatted(
            .relative(presentation: .named)
                .locale(BSmartLocalization.formattingLocale)
        )
    }
}

extension PortfolioSignalPersonalization {
    var localizedContextSummary: String {
        switch relationship {
        case .watchlist:
            return "Watchlist · no capital exposed".bSmartLocalized
        case .untracked:
            return "Outside your portfolio".bSmartLocalized
        case .position:
            let exposure = positionWeight?.formatted(.percent.precision(.fractionLength(0)))
                ?? "Held position".bSmartLocalized
            let cost = costDistancePercent.map(localizedCostDistance)
                ?? "cost not entered".bSmartLocalized
            return "\(exposure) · \(cost)"
        }
    }

    func localizedImpactText(for signal: PortfolioSignal) -> String {
        switch relationship {
        case .watchlist:
            return "You are watching %@, but no portfolio capital is exposed. Use this change to decide whether the ticker still belongs on your research list."
                .bSmartLocalized(signal.ticker)
        case .untracked:
            return "%@ is outside your portfolio and watchlist. Compare this evidence with the exposures you already hold before adding it to your research list."
                .bSmartLocalized(signal.ticker)
        case .position:
            let exposure = positionWeight.map {
                "%@ of your portfolio".bSmartLocalized($0.formatted(.percent.precision(.fractionLength(0))))
            } ?? "a held position".bSmartLocalized

            let opening: String
            if let costDistancePercent {
                opening = "%@ is %@ and trades %@."
                    .bSmartLocalized(signal.ticker, exposure, localizedCostDistance(costDistancePercent))
            } else {
                opening = "%@ is %@. Add a cost basis to place this change against your entry."
                    .bSmartLocalized(signal.ticker, exposure)
            }
            return "\(opening) \(localizedRelationshipInterpretation(for: signal))"
        }
    }

    func localizedAttentionReason(for signal: PortfolioSignal) -> String {
        var factors: [String] = []
        switch relationship {
        case .position:
            if let positionWeight {
                factors.append("a %@ position".bSmartLocalized(
                    positionWeight.formatted(.percent.precision(.fractionLength(0)))
                ))
            } else {
                factors.append("a held position".bSmartLocalized)
            }
            if let costDistancePercent {
                factors.append(localizedCostDistance(costDistancePercent))
            }
        case .watchlist:
            factors.append("a watched ticker".bSmartLocalized)
        case .untracked:
            factors.append("an untracked ticker".bSmartLocalized)
        }

        let evidenceFactor = switch signal.kind {
        case .divergence: "evidence is diverging"
        case .confirmation: "independent evidence agrees"
        case .accountLeads: "capital confirmation is absent"
        case .moneyLeads: "capital moved first"
        default: "a qualified source changed"
        }
        factors.append(evidenceFactor.bSmartLocalized)
        if signal.resolvedDataStatus == .delayed {
            factors.append("data is delayed".bSmartLocalized)
        }

        return "Marked %@ because this is %@."
            .bSmartLocalized(attention.label.bSmartLocalized.lowercased(), localizedJoinedFactors(factors))
    }

    private func localizedCostDistance(_ value: Double) -> String {
        let magnitude = abs(value).formatted(.percent.precision(.fractionLength(1)))
        if abs(value) < 0.005 { return "near your cost".bSmartLocalized }
        let key = value > 0 ? "%@ above your cost" : "%@ below your cost"
        return key.bSmartLocalized(magnitude)
    }

    private func localizedRelationshipInterpretation(for signal: PortfolioSignal) -> String {
        let key = switch signal.kind {
        case .divergence where (costDistancePercent ?? 0) < 0:
            "Qualified views and public capital disagree while the position is below cost, so the thesis and downside limit deserve closer review."
        case .divergence:
            "Qualified views and public capital disagree, so follow-through and the thesis invalidation level matter more than either signal alone."
        case .confirmation where (positionWeight ?? 0) >= 0.25:
            "Independent evidence confirms the current direction, but the concentration makes follow-through and the invalidation level especially important."
        case .confirmation:
            "Independent evidence confirms the current direction; monitor whether both sources continue to agree."
        case .accountLeads:
            "The creator view moved first and has no qualifying capital confirmation, so treat it as a thesis update rather than a funded market signal."
        case .moneyLeads:
            "Public capital moved first; look for an independent Smart Account view before treating the move as broader confirmation."
        case .smartAccountNewView, .smartAccountShift, .smartAccountConsensus:
            "This is a change in qualified investor views; compare its assumptions and invalidation condition with your holding plan."
        case .smartMoneyMovement:
            "This is an observable public-capital change; monitor whether it persists and gains independent account support."
        }
        return key.bSmartLocalized
    }

    private func localizedJoinedFactors(_ factors: [String]) -> String {
        guard let last = factors.last else { return "relevant to your portfolio".bSmartLocalized }
        if factors.count == 1 { return last }
        if BSmartLocalization.isSimplifiedChinese {
            return factors.joined(separator: "、")
        }
        if factors.count == 2 { return factors.joined(separator: " and ") }
        return factors.dropLast().joined(separator: ", ") + ", and " + last
    }
}
