import SwiftUI

struct OpinionSupportingSourcesSection: View {
    let sources: [OpinionSupportingSource]

    var body: some View {
        if !sources.isEmpty {
            VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
                HStack {
                    Text("Supporting sources".bSmartLocalized)
                        .font(.headline.weight(.bold))
                    Spacer()
                    Text(sources.count.formatted())
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(BSmartColor.secondaryText)
                }
                ForEach(Array(sources.prefix(2))) { source in
                    OpinionSourceLink(source: source)
                }
                if sources.count > 2 {
                    BSmartDetailNavigationLink(id: "opinion.sources.all") {
                        OpinionSupportingSourcesList(sources: sources)
                    } label: {
                        HStack {
                            Text("All supporting sources".bSmartLocalized)
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BSmartColor.brand)
                        .padding(.vertical, BSmartSpacing.small)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("opinion.sources.all")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("opinion.sources")
        }
    }
}

private struct OpinionSourceLink: View {
    let source: OpinionSupportingSource

    var body: some View {
        BSmartDetailNavigationLink(id: source.id) {
            OpinionSupportingSourceDetailView(source: source)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                OpinionSourceIdentity(source: source)
                Text(source.displayTitle)
                    .font(.headline)
                    .foregroundStyle(BSmartColor.primaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Text(source.displaySummary)
                    .font(.subheadline)
                    .foregroundStyle(BSmartColor.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .firstTextBaseline) {
                    Text(source.cardDateLabel)
                        .foregroundStyle(BSmartColor.secondaryText)
                    Spacer(minLength: 8)
                    Text(source.relationshipLabel)
                        .foregroundStyle(BSmartColor.brand)
                    Image(systemName: "arrow.up.right")
                        .foregroundStyle(BSmartColor.brand)
                }
                .font(.caption)
            }
            .padding(BSmartSpacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BSmartColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(BSmartColor.line, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("opinion.source.open.\(source.id)")
    }
}

private struct OpinionSupportingSourcesList: View {
    let sources: [OpinionSupportingSource]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: BSmartSpacing.medium) {
                ForEach(sources) { OpinionSourceLink(source: $0) }
            }
            .padding(BSmartSpacing.large)
        }
        .navigationTitle("Supporting sources".bSmartLocalized)
        .navigationBarTitleDisplayMode(.inline)
        .bSmartDetailPage()
        .bSmartPage()
    }
}

struct OpinionSupportingSourceDetailView: View {
    let source: OpinionSupportingSource

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BSmartSpacing.large) {
                OpinionSourceIdentity(source: source)
                Text(source.displayTitle)
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                HStack(alignment: .firstTextBaseline) {
                    Text(source.publishedDateLabel)
                    Spacer()
                    Text(source.relationshipLabel)
                }
                .font(.caption)
                .foregroundStyle(BSmartColor.secondaryText)

                if let updated = source.updatedAt {
                    Text("Source updated %@".bSmartLocalized(updated.formatted(date: .abbreviated, time: .shortened)))
                        .font(.caption)
                        .foregroundStyle(BSmartColor.secondaryText)
                }

                textSection("Source summary", text: source.displaySummary)
                Divider().overlay(BSmartColor.line)
                textSection("Related statement", text: source.claim)

                VStack(alignment: .leading, spacing: BSmartSpacing.small) {
                    Label("Source excerpt".bSmartLocalized, systemImage: "quote.opening")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BSmartColor.brand)
                    Text(source.excerpt)
                        .font(.body)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(source.locator)
                        .font(.caption)
                        .foregroundStyle(BSmartColor.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(BSmartSpacing.medium)
                .background(BSmartColor.brand.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if let note = source.displayContextNote {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(BSmartColor.secondaryText)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let url = source.originalURL {
                    Link(destination: url) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Open original source".bSmartLocalized)
                                    .font(.subheadline.weight(.semibold))
                                Text(url.host ?? source.publisher)
                                    .font(.caption)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                        }
                        .foregroundStyle(BSmartColor.brand)
                        .padding(.vertical, BSmartSpacing.medium)
                    }
                    .accessibilityIdentifier("opinion.source.original")
                }
            }
            .padding(BSmartSpacing.large)
        }
        .navigationTitle("Supporting source".bSmartLocalized)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("opinion.source.detail")
        .bSmartDetailPage()
        .bSmartPage()
    }

    private func textSection(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.small) {
            Text(title.bSmartLocalized)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BSmartColor.secondaryText)
            Text(text)
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct OpinionSourceIdentity: View {
    let source: OpinionSupportingSource

    var body: some View {
        HStack(alignment: .center, spacing: BSmartSpacing.small) {
            Image(systemName: source.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(BSmartColor.brand)
                .frame(width: 34, height: 34)
                .background(BSmartColor.brand.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.publisher).font(.subheadline.weight(.semibold))
                Text(source.typeLabel)
                    .font(.caption)
                    .foregroundStyle(BSmartColor.secondaryText)
            }
            Spacer(minLength: 6)
            BSmartAssetMark(ticker: source.ticker, size: 28)
                .accessibilityLabel(source.ticker)
        }
    }
}

private extension OpinionSupportingSource {
    var cardDateLabel: String {
        if relationship == "follow_up", let updatedAt {
            return "Source updated %@".bSmartLocalized(updatedAt.formatted(date: .abbreviated, time: .omitted))
        }
        return publishedDateLabel
    }
    var publishedDateLabel: String {
        publishedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted,
                                               timeZone: TimeZone(secondsFromGMT: 0)!))
    }
    var displayTitle: String { localized(title, titleZH) }
    var displaySummary: String { localized(summary, summaryZH) }
    var displayContextNote: String? {
        let note = localized(contextNote ?? "", contextNoteZH)
        return note.isEmpty ? nil : note
    }
    func localized(_ english: String, _ chinese: String?) -> String {
        guard BSmartLocalization.isSimplifiedChinese, let chinese,
              !chinese.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return english }
        return chinese
    }
    var relationshipLabel: String {
        switch relationship {
        case "cited": return "Cited by author".bSmartLocalized
        case "follow_up": return "Subsequent update".bSmartLocalized
        default: return "Related material".bSmartLocalized
        }
    }
    var typeLabel: String {
        switch sourceType {
        case "company": return "Company disclosure".bSmartLocalized
        case "regulatory": return "Regulatory filing".bSmartLocalized
        case "news": return "News report".bSmartLocalized
        case "research": return "Research".bSmartLocalized
        case "data": return "Data release".bSmartLocalized
        default: return "Source material".bSmartLocalized
        }
    }
    var symbol: String {
        switch sourceType {
        case "company": return "building.2"
        case "regulatory": return "doc.text"
        case "news": return "newspaper"
        case "research": return "book.closed"
        case "data": return "chart.bar.xaxis"
        default: return "link"
        }
    }
}
