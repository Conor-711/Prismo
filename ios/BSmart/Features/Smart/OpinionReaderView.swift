import SwiftUI

struct OpinionReaderView: View {
    let update: SmartAccountUpdate
    @State private var prefersOriginal = false
    @AppStorage("bsmart.opinion.reading.size") private var readingSize = "standard"
    @ScaledMetric(relativeTo: .body) private var compactSize = 15.0
    @ScaledMetric(relativeTo: .body) private var standardSize = 17.0
    @ScaledMetric(relativeTo: .body) private var largeSize = 19.0

    private var content: OpinionReadingContent {
        OpinionReadingContent(update: update, chinese: BSmartLocalization.isSimplifiedChinese)
    }
    private var showingTranslation: Bool { content.translation != nil && (!prefersOriginal || content.original == nil) }
    private var displayedText: String? { showingTranslation ? content.translation : content.original }
    private var fontSize: Double {
        switch readingSize {
        case "compact": compactSize
        case "large": largeSize
        default: standardSize
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let summary = content.summary {
                VStack(alignment: .leading, spacing: 8) {
                    Text("bSmart summary".bSmartLocalized)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BSmartColor.brand)
                    Text(summary)
                        .font(.title3.weight(.semibold))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("opinion.reader.summary")
                }
            }

            VStack(alignment: .leading, spacing: 20) {
                controls
                if let text = displayedText {
                    let document = OpinionReadingDocument(text: text, evidence: showingTranslation ? nil : update.evidenceSpan)
                    VStack(alignment: .leading, spacing: 16) {
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
                            .textSelection(.enabled)
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
            Menu {
                Picker("Text size".bSmartLocalized, selection: $readingSize) {
                    Text("Compact".bSmartLocalized).tag("compact")
                    Text("Standard".bSmartLocalized).tag("standard")
                    Text("Large".bSmartLocalized).tag("large")
                }
            } label: {
                Image(systemName: "textformat.size").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Text size".bSmartLocalized)
            .accessibilityValue((readingSize == "compact" ? "Compact" : readingSize == "large" ? "Large" : "Standard").bSmartLocalized)
            .accessibilityIdentifier("opinion.reader.text-size")
            .help("Text size".bSmartLocalized)

            if let text = displayedText {
                Button {
                    UIPasteboard.general.string = text
                } label: {
                    Image(systemName: "doc.on.doc").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Copy text".bSmartLocalized)
                .accessibilityIdentifier("opinion.reader.copy")
                .help("Copy text".bSmartLocalized)
            }
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
            .padding(.top, block.isHeading && block.id > 0 ? 6 : 0)
            .textSelection(.enabled)
    }
}
