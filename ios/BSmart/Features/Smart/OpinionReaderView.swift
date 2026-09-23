import SwiftUI

struct OpinionReaderView: View {
    let update: SmartAccountUpdate
    @State private var prefersOriginal = false
    @ScaledMetric(relativeTo: .body) private var fontSize = 17.0

    private var content: OpinionReadingContent {
        OpinionReadingContent(update: update, chinese: BSmartLocalization.isSimplifiedChinese)
    }
    private var showingTranslation: Bool { content.translation != nil && (!prefersOriginal || content.original == nil) }
    private var displayedText: String? { showingTranslation ? content.translation : content.original }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let summary = content.summary {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Summary".bSmartLocalized)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BSmartColor.brand)
                    Text(summary)
                        .font(.system(size: fontSize, weight: .regular))
                        .foregroundStyle(BSmartColor.primaryText)
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("opinion.reader.summary")
                }
            }

            VStack(alignment: .leading, spacing: 20) {
                controls
                if let text = displayedText {
                    let document = OpinionReadingDocument(text: text, evidence: showingTranslation ? nil : update.evidenceSpan,
                                                          ticker: update.ticker)
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(document.blocks) { block in
                            paragraph(block)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(showingTranslation ? "opinion.reader.translation" : "opinion.reader.original")
                } else if let span = update.evidenceSpan, !span.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Evidence excerpt".bSmartLocalized)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BSmartColor.brand)
                        Text(span)
                            .font(.system(size: fontSize))
                            .lineSpacing(7)
                        Text("The complete source text is unavailable; only the extracted evidence is shown.".bSmartLocalized)
                            .font(.caption)
                            .foregroundStyle(BSmartColor.secondaryText)
                    }
                } else {
                    Text("The complete source text is unavailable.".bSmartLocalized)
                        .font(.subheadline)
                        .foregroundStyle(BSmartColor.secondaryText)
                }
            }
            if let imageURLs = update.imageURLs, !imageURLs.isEmpty {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(imageURLs, id: \.self) { url in
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().scaledToFit()
                                case .failure:
                                    Image(systemName: "photo")
                                        .foregroundStyle(BSmartColor.secondaryText)
                                case .empty:
                                    ProgressView()
                                @unknown default:
                                    EmptyView()
                                }
                            }
                            .frame(width: imageURLs.count == 1 ? 320 : 260, height: 260)
                            .background(BSmartColor.line.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .accessibilityIdentifier("opinion.reader.photos")
            }
            Divider().overlay(BSmartColor.line)
        }
        .frame(maxWidth: 680, alignment: .leading)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("opinion.reader")
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                versions
                Spacer(minLength: 8)
                actions
            }
            VStack(alignment: .leading, spacing: 8) {
                versions
                actions
            }
        }
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(BSmartColor.line).frame(height: 1) }
    }

    private var versions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) { versionChoices }
                .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 4) {
                versionChoices
            }
        }
    }

    @ViewBuilder private var versionChoices: some View {
        if content.translation != nil {
            versionButton("Translation", selected: showingTranslation, original: false)
        }
        if content.original != nil {
            versionButton("Original", selected: !showingTranslation, original: true)
        }
    }

    private func versionButton(_ title: String, selected: Bool, original: Bool) -> some View {
        Button {
            prefersOriginal = original
        } label: {
            Text(title.bSmartLocalized)
                .font(.subheadline.weight(selected ? .semibold : .medium))
                .foregroundStyle(selected ? BSmartColor.primaryText : BSmartColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 44)
                .overlay(alignment: .bottom) {
                    if selected { Capsule().fill(BSmartColor.brand).frame(height: 2) }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(original ? "opinion.reader.show-original" : "opinion.reader.show-translation")
    }

    private var actions: some View {
        HStack(spacing: 0) {
            if let url = update.sourceURL ?? update.evidenceURL {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right.square").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Open original source".bSmartLocalized)
                .accessibilityIdentifier("opinion.reader.source")
                .help("Open original source".bSmartLocalized)
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(BSmartColor.secondaryText)
    }

    private func paragraph(_ block: OpinionReadingDocument.Block) -> some View {
        var value = AttributedString(block.text)
        for nsRange in block.inlineEmphasis {
            if let range = Range(nsRange, in: block.text),
               let attributedRange = Range(range, in: value) {
                value[attributedRange].font = .system(size: fontSize, weight: .semibold)
            }
        }
        for nsRange in block.emphasis {
            if let range = Range(nsRange, in: block.text),
               let attributedRange = Range(range, in: value) {
                value[attributedRange].font = .system(size: fontSize, weight: .semibold)
                value[attributedRange].backgroundColor = BSmartColor.brand.opacity(0.12)
            }
        }
        return Text(value)
            .font(.system(size: fontSize, weight: block.isHeading ? .semibold : .regular))
            .foregroundStyle(BSmartColor.primaryText)
            .lineSpacing(7)
            .tracking(0)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, block.startsNewParagraph && block.id > 0 ? 14 : 0)
    }
}
