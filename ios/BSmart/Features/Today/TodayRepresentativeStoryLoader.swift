import SwiftUI

struct TodayRepresentativeStoryLoader: View {
    @EnvironmentObject private var model: AppModel
    let account: SmartAccountProfile
    @State private var story: TodayRepresentativeStory?
    @State private var isLoading = true
    @State private var retry = 0

    init(account: SmartAccountProfile) {
        self.account = account
        let bundled = TodayRepresentativeStoryBundle.bundled?.story(for: account)
        _story = State(initialValue: bundled)
        _isLoading = State(initialValue: bundled == nil && account.representativeWork?.direction == .bullish
            && account.representativeWork?.firstOpinion?.referencePrice != nil)
    }

    private var highlight: TodayInvestorDiscoveryHighlight {
        TodayInvestorDiscoveryHighlight(account: account, representatives: model.representativeAccountEvidence(for: account))
    }
    private var evidence: [SmartAccountUpdate] {
        model.accountEvidence(for: account) + model.accountUpdates(for: account)
    }

    var body: some View {
        Group {
            if let story {
                TodayRepresentativeStoryCard(story: story)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    if let intro = highlight.intro {
                        HStack(spacing: 6) {
                            BSmartAssetMark(ticker: intro.ticker, size: 20)
                            Text(intro.ticker).font(.subheadline.bold())
                            Text("Representative work".bSmartLocalized).font(.caption)
                        }
                        if let first = highlight.firstOpinion {
                            Text(first.direction.label.bSmartLocalized).font(.caption)
                            if let value = first.referencePrice {
                                Text("Price %@".bSmartLocalized(TodayRepresentativeStoryCopy.price(value))).font(.subheadline)
                            }
                            if let url = first.evidenceURL {
                                Link("Open original source".bSmartLocalized, destination: url).font(.caption)
                            }
                        }
                    }
                    if isLoading {
                        BSmartSkeletonRows(style: .feed, count: 1)
                    } else if highlight.intro?.direction == .bullish && highlight.firstOpinion?.referencePrice != nil {
                        Button { retry += 1 } label: {
                            Label("Reload price history".bSmartLocalized, systemImage: "arrow.clockwise")
                                .font(.caption).frame(minHeight: 44)
                        }.buttonStyle(.plain)
                    }
                }.padding(.vertical, 10).foregroundStyle(BSmartColor.secondaryText)
            }
        }
        .task(id: retry) {
            rebuild()
            guard highlight.intro?.direction == .bullish, highlight.firstOpinion?.referencePrice != nil
            else { isLoading = false; return }
            isLoading = story == nil
            // Let portrait scrolling settle before fetching full daily-price evidence.
            do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
            guard !Task.isCancelled else { return }
            await model.loadSmartAccountEvidence(for: account, refresh: retry > 0)
            guard !Task.isCancelled else { return }
            rebuild()
            isLoading = false
        }
        .onChange(of: evidence) { _, _ in rebuild() }
        .onChange(of: account.representativeWork) { _, _ in rebuild() }
    }

    private func rebuild() {
        if model.smartAccountEvidenceByAuthor[account.id] != nil,
           let fresh = TodayRepresentativeStory(account: account, intro: highlight.intro, evidence: evidence) {
            story = fresh
        } else if story?.anchor.id != highlight.intro?.evidenceId {
            story = TodayRepresentativeStoryBundle.bundled?.story(for: account)
        }
    }
}
