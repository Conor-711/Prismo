import Foundation

struct OpinionSupportingSource: Identifiable, Codable, Hashable {
    let id: String
    let eventId: String
    let ticker: String
    let publisher: String
    let sourceType: String
    let relationship: String
    let status: String
    let title: String
    let summary: String
    let publishedAt: Date
    let sourceURL: String
    let claim: String
    let excerpt: String
    let locator: String
    var updatedAt: Date? = nil
    var titleZH: String? = nil
    var summaryZH: String? = nil
    var contextNote: String? = nil
    var contextNoteZH: String? = nil

    var originalURL: URL? {
        guard !sourceURL.contains("\\"), !sourceURL.contains(where: { $0.isWhitespace }),
              let url = URL(string: sourceURL), url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(), host.contains("."),
              url.user == nil, url.password == nil,
              host != "localhost", !host.hasSuffix(".local"),
              !host.hasSuffix(".localhost"), !host.hasSuffix(".internal"),
              url.port == nil || url.port == 443,
              !host.contains(":"), host.rangeOfCharacter(from: .letters) != nil else { return nil }
        return url
    }

    func isDisplayable(for update: SmartAccountUpdate, now: Date = Date()) -> Bool {
        guard status == "ready", ticker.uppercased() == update.ticker.uppercased(),
              ["company", "regulatory", "news", "research", "data", "other"].contains(sourceType),
              ["cited", "related", "follow_up"].contains(relationship),
              [id, eventId, publisher, title, summary, claim, excerpt, locator].allSatisfy({
                  !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              }), originalURL != nil, publishedAt <= now,
              update.originalText?.contains(claim) == true else { return false }
        if let updatedAt, updatedAt < publishedAt || updatedAt > now { return false }
        let availableAt = max(publishedAt, updatedAt ?? publishedAt)
        return relationship == "follow_up" ? availableAt > update.publishedAt : availableAt <= update.publishedAt
    }
}

extension SmartAccountUpdate {
    var displayableSupportingSources: [OpinionSupportingSource] {
        var ids = Set<String>()
        var urls = Set<String>()
        return (supportingSources ?? []).filter { source in
            guard source.isDisplayable(for: self),
                  var components = URLComponents(string: source.sourceURL) else { return false }
            components.fragment = nil
            components.host = components.host?.lowercased()
            let key = components.string ?? source.sourceURL
            guard !ids.contains(source.id), !urls.contains(key) else { return false }
            ids.insert(source.id)
            urls.insert(key)
            return true
        }
    }
}
