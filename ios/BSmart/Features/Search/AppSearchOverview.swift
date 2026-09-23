import SwiftUI

struct AppSearchOverviewData {
    var tickers: [AppSearchItem] = []
    var opinions: [AppSearchItem] = []
    var authors: [AppSearchItem] = []

    init(items: [AppSearchItem] = [], trendingSymbols: [String] = []) {
        let ranks = Dictionary(trendingSymbols.enumerated().map { ($0.element.uppercased(), $0.offset) },
                               uniquingKeysWith: min)
        tickers = Array(items.filter { $0.category == .tickers }.sorted {
            let lhs = ranks[$0.ticker ?? ""] ?? Int.max, rhs = ranks[$1.ticker ?? ""] ?? Int.max
            return lhs == rhs ? $0.id < $1.id : lhs < rhs
        }.prefix(6))
        var seen = Set<String>()
        opinions = Array(items.filter { $0.category == .opinions && seen.insert($0.id).inserted }
            .sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }.prefix(4))
        authors = Array(items.filter { $0.category == .authors }.prefix(8))
    }
}

struct AppSearchOverview: View {
    let data: AppSearchOverviewData
    let open: (AppSearchItem) -> Void
    @ScaledMetric(relativeTo: .caption) private var minimumTileWidth = 152.0
    @ScaledMetric(relativeTo: .caption) private var nameHeight = 18.0
    @ScaledMetric(relativeTo: .caption2) private var rankHeight = 22.0

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            if !data.tickers.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    heading("Trending Tickers")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumTileWidth), spacing: 10)], spacing: 10) {
                        ForEach(data.tickers) { item in
                            if case .ticker(let entry) = item {
                                Button { open(item) } label: {
                                    HStack(spacing: 10) {
                                        BSmartAssetMark(ticker: entry.symbol, size: 32)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(entry.symbol).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                                                .accessibilityIdentifier("search.tile.symbol.\(entry.symbol)")
                                            Text(entry.price?.bSmartMarketPrice ?? "—").font(.caption).monospacedDigit()
                                                .foregroundStyle(BSmartColor.secondaryText).lineLimit(1).minimumScaleFactor(0.7)
                                                .accessibilityIdentifier("search.tile.price.\(entry.symbol)")
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(12)
                                    .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
                                    .background(BSmartColor.surface, in: RoundedRectangle(cornerRadius: 8))
                                    .overlay { RoundedRectangle(cornerRadius: 8).stroke(BSmartColor.line.opacity(0.6), lineWidth: 0.5) }
                                    .contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityIdentifier("search.overview.\(item.id)")
                            }
                        }
                    }
                }.accessibilityElement(children: .contain).accessibilityIdentifier("search.overview.tickers")
            }
            if !data.authors.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    heading("Discover investors")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(data.authors) { item in
                                Button { open(item) } label: {
                                    VStack(spacing: 10) {
                                        if case .author(let value) = item {
                                            BSmartAvatar(url: value.avatarURL, name: value.name, size: 58)
                                        } else if case .money(let value) = item {
                                            BSmartSmartMoneyAvatar(identity: value.publicIdentity, size: 58)
                                        }
                                        VStack(spacing: 4) {
                                            Text(item.title).font(.caption.weight(.semibold))
                                                .lineLimit(1).truncationMode(.tail).frame(height: nameHeight)
                                            Group {
                                                if let rank = item.investorRanking {
                                                    Text(rank).font(.caption2.weight(.bold)).monospacedDigit()
                                                        .foregroundStyle(BSmartColor.brand)
                                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                                        .background(BSmartColor.brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                                                        .accessibilityIdentifier("search.investor.rank.\(item.id)")
                                                } else {
                                                    Color.clear.accessibilityHidden(true)
                                                }
                                            }.frame(height: rankHeight)
                                        }
                                    }.frame(width: 104)
                                }.buttonStyle(.plain).accessibilityIdentifier("search.overview.\(item.id)")
                                    .accessibilityLabel([item.title, item.investorRanking].compactMap { $0 }.joined(separator: ", "))
                            }
                        }.padding(.vertical, 2)
                    }
                }.accessibilityElement(children: .contain).accessibilityIdentifier("search.overview.authors")
            }
            if !data.opinions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    heading("Latest views")
                    ForEach(data.opinions) { item in
                        Button { open(item) } label: { AppSearchResultRow(item: item) }
                            .buttonStyle(.plain).accessibilityIdentifier("search.overview.\(item.id)")
                    }
                }.accessibilityElement(children: .contain).accessibilityIdentifier("search.overview.opinions")
            }
        }.foregroundStyle(BSmartColor.primaryText)
    }
    private func heading(_ title: String) -> some View {
        Text(title.bSmartLocalized).font(.headline).padding(.bottom, 8)
    }
}
