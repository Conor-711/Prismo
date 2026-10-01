import Foundation

/// A conservative explanation of disclosed long-option exposure, not an investor sentiment score.
struct SubjectOptionInterpretation: Equatable {
    enum Kind { case call, put, unknown }
    enum Change { case added, reduced, held, omitted, unknown }
    let kind: Kind
    let change: Change

    init?(event: TodaySubjectEvent) {
        guard event.type == .holding, !event.isSample else { return nil }
        switch event.summary?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "CALL OPTION": kind = .call
        case "PUT OPTION": kind = .put
        default:
            guard event.ticker == nil, event.underlyingTicker != nil else { return nil }
            kind = .unknown
        }
        switch event.action {
        case "new", "increased": change = .added
        case "reduced": change = .reduced
        case "held": change = .held
        case "no_longer_reported": change = .omitted
        default: change = .unknown
        }
    }

    var titleKey: String {
        guard kind != .unknown else { return "Direction cannot be confirmed" }
        switch (kind, change) {
        case (.call, .added): return "Bullish exposure increased"
        case (.put, .added): return "Bearish or hedging exposure increased"
        case (.call, .reduced): return "Bullish exposure reduced"
        case (.put, .reduced): return "Bearish or hedging exposure reduced"
        case (.call, .held): return "Bullish option exposure reported"
        case (.put, .held): return "Bearish or hedging option exposure reported"
        case (_, .omitted): return "Option position no longer reported"
        default: return "Direction cannot be confirmed"
        }
    }

    var explanationKey: String {
        guard kind != .unknown else {
            return "The disclosed information does not establish the option type or overall direction."
        }
        switch (kind, change) {
        case (_, .omitted):
            return "Absent from this filing does not confirm a closing trade or a reversal in outlook."
        case (.call, .added):
            return "Reported long-call exposure increased. This can be part of a spread or hedge, not proof of an overall bullish view."
        case (.put, .added):
            return "Reported long-put exposure increased. This may express a bearish view or protect stock holdings; the filing cannot distinguish them."
        case (.call, .reduced):
            return "Reported long-call exposure decreased. Reducing bullish exposure does not establish a bearish view."
        case (.put, .reduced):
            return "Reported long-put exposure decreased. Reducing bearish or protective exposure does not establish a bullish view."
        case (.call, .held):
            return "A long-call position was reported. It may be part of a wider strategy whose net direction is not disclosed."
        case (.put, .held):
            return "A long-put position was reported. It may be a bearish position or protection for other holdings."
        default:
            return "The disclosed information does not establish the option type or overall direction."
        }
    }
}
