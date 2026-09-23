import SwiftUI
import UIKit

struct OpinionReaderView: View {
    let update: SmartAccountUpdate
    @State private var prefersOriginal = false
    @State private var selectedPhoto: OpinionPhotoSelection?
    @ScaledMetric(relativeTo: .body) private var fontSize = 17.0

    private var content: OpinionReadingContent {
        OpinionReadingContent(update: update, chinese: BSmartLocalization.isSimplifiedChinese)
    }
    private var showingTranslation: Bool { content.translation != nil && (!prefersOriginal || content.original == nil) }
    private var displayedText: String? { showingTranslation ? content.translation : content.original }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                .padding(.bottom, 22)
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
                VStack(spacing: 10) {
                    ForEach(imageURLs, id: \.self) { url in
                        OpinionInlinePhoto(url: url) { image in
                            selectedPhoto = OpinionPhotoSelection(url: url, image: image)
                        }
                    }
                }
                .padding(.top, 14)
                .accessibilityIdentifier("opinion.reader.photos")
            }
            Divider().overlay(BSmartColor.line)
                .padding(.top, 20)
        }
        .frame(maxWidth: 680, alignment: .leading)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("opinion.reader")
        .fullScreenCover(item: $selectedPhoto) { photo in
            OpinionPhotoViewer(image: photo.image)
        }
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

private struct OpinionPhotoSelection: Identifiable {
    let url: URL
    let image: UIImage
    var id: URL { url }
}

private struct OpinionInlinePhoto: View {
    let url: URL
    let onSelect: (UIImage) -> Void
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Button { onSelect(image) } label: {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(image.size.width / max(image.size.height, 1), contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View image".bSmartLocalized)
            } else if failed {
                Image(systemName: "photo")
                    .foregroundStyle(BSmartColor.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
            }
        }
        .task(id: url) {
            if image != nil { return }
            image = nil
            failed = false
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard !Task.isCancelled else { return }
                guard let response = response as? HTTPURLResponse,
                      (200...299).contains(response.statusCode),
                      let decoded = UIImage(data: data) else {
                    failed = true
                    return
                }
                image = decoded
            } catch {
                if !Task.isCancelled { failed = true }
            }
        }
    }
}

private struct OpinionPhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            GeometryReader { geometry in
                ZoomableOpinionPhoto(image: image, viewport: geometry.size)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close".bSmartLocalized)
            .padding(16)
        }
        .statusBarHidden()
        .accessibilityIdentifier("opinion.photo.viewer")
    }
}

private struct ZoomableOpinionPhoto: UIViewRepresentable {
    let image: UIImage
    let viewport: CGSize

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = .black
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 6
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        context.coordinator.scrollView = scrollView
        scrollView.addSubview(context.coordinator.imageView)
        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.doubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        let coordinator = context.coordinator
        guard coordinator.displayedImage !== image || coordinator.viewport != viewport else { return }
        coordinator.displayedImage = image
        coordinator.viewport = viewport
        coordinator.imageView.image = image
        let width = max(viewport.width, 1)
        let height = max(viewport.height, 1)
        let fit = min(width / max(image.size.width, 1), height / max(image.size.height, 1))
        let size = CGSize(width: image.size.width * fit, height: image.size.height * fit)
        scrollView.zoomScale = 1
        coordinator.imageView.frame = CGRect(origin: .zero, size: size)
        scrollView.contentSize = size
        coordinator.centerImage()
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let imageView = UIImageView()
        weak var scrollView: UIScrollView?
        var displayedImage: UIImage?
        var viewport: CGSize = .zero

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage() }

        func centerImage() {
            guard let scrollView else { return }
            imageView.center = CGPoint(
                x: max(scrollView.contentSize.width, scrollView.bounds.width) / 2,
                y: max(scrollView.contentSize.height, scrollView.bounds.height) / 2
            )
        }

        @objc func doubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView else { return }
            if scrollView.zoomScale > 1 {
                scrollView.setZoomScale(1, animated: true)
            } else {
                let scale: CGFloat = 3
                let point = gesture.location(in: imageView)
                scrollView.zoom(to: CGRect(
                    x: point.x - scrollView.bounds.width / (2 * scale),
                    y: point.y - scrollView.bounds.height / (2 * scale),
                    width: scrollView.bounds.width / scale,
                    height: scrollView.bounds.height / scale
                ), animated: true)
            }
        }
    }
}
