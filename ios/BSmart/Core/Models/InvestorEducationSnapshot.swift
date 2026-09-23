import Foundation

struct InvestorEducationSnapshot: Decodable, Sendable {
    struct Author: Decodable, Identifiable, Sendable {
        let id: String
        let name: String
        let rank: Int
        let tile: Int
    }
    struct Platform: Decodable, Identifiable, Sendable {
        let id, name: String
        let totalObserved, rankedCount, selectedCount: Int
        let authors: [Author]
        var headlineCount: String { totalObserved >= 1000 ? "1000+" : String(totalObserved) }
        var isValid: Bool {
            totalObserved >= rankedCount && rankedCount >= selectedCount && selectedCount > 0 &&
            selectedCount == rankedCount / 4 && !authors.isEmpty && authors.count <= totalObserved &&
            authors.allSatisfy { author in
                (0...rankedCount).contains(author.rank) &&
                (id == "x" ? !author.id.contains(":") : author.id.hasPrefix("\(id):"))
            }
        }
    }
    struct Point: Decodable, Identifiable, Sendable {
        let day: String
        let close: Double
        var id: String { day }
        var date: Date { Self.formatter.date(from: day) ?? .distantPast }
        private static var formatter: DateFormatter {
            let value = DateFormatter()
            value.locale = Locale(identifier: "en_US_POSIX")
            value.timeZone = TimeZone(secondsFromGMT: 0)
            value.dateFormat = "yyyy-MM-dd"
            return value
        }
    }
    struct Example: Decodable, Sendable {
        let id, authorID, authorName, handle, avatarURL: String
        let rank: Int
        let percentile: Double
        let settledCalls: Int
        let ticker, publishedAt, sourceURL, summaryZH, summaryEN: String
        let entryDay, exitDay: String
        let entryPrice, exitPrice, returnPercent, contribution: Double
        let horizon, source: String
        let candles: [Point]
        var summary: String { BSmartLocalization.isSimplifiedChinese ? summaryZH : summaryEN }
        var publishedDay: String { String(publishedAt.prefix(10)) }
    }
    let snapshotDate: String
    let columns, tile, atlasWidth, atlasHeight: Int
    let platforms: [Platform]
    static let defaultPlatformID = "x"
    var displayPlatforms: [Platform] {
        ["youtube", "x", "reddit"].compactMap { id in platforms.first { $0.id == id } }
    }
    var authors: [Author] { platforms.flatMap(\.authors) }
    let example: Example

    var isValid: Bool {
        platforms.count == 3 && Set(platforms.map(\.id)) == Set(["x", "youtube", "reddit"]) &&
        platforms.allSatisfy(\.isValid) &&
        columns > 0 && tile > 0 && atlasWidth == columns * tile && atlasHeight > 0 &&
        Set(authors.map(\.id)).count == authors.count &&
        Set(authors.map(\.tile)).count == authors.count &&
        authors.allSatisfy { $0.tile >= 0 && ($0.tile / columns + 1) * tile <= atlasHeight } &&
        example.contribution > 0 && example.returnPercent > 0 && example.entryPrice > 0 &&
        example.exitDay > example.entryDay && example.candles.count > 2 &&
        example.candles.allSatisfy { $0.close.isFinite && $0.close > 0 } &&
        zip(example.candles, example.candles.dropFirst()).allSatisfy { $0.day < $1.day }
    }

    static func load(bundle: Bundle = .main) throws -> Self {
        guard let url = bundle.url(forResource: "InvestorEducation", withExtension: "plist") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let value = try PropertyListDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard value.isValid else { throw CocoaError(.fileReadCorruptFile) }
        return value
    }
}
