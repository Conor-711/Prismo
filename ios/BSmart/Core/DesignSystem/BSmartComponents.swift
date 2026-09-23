import SwiftUI

struct BSmartSkeletonBar: View {
    var width: CGFloat? = nil
    var height: CGFloat = 12
    var circular = false

    var body: some View {
        RoundedRectangle(cornerRadius: circular ? height / 2 : min(6, height / 2))
        .fill(BSmartColor.tertiaryText.opacity(0.34))
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }
}

struct BSmartSkeletonRows: View {
    enum Style { case ranking, feed, chat, profile, simple }
    let style: Style
    var count = 3
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                rows
            } else {
                rows.phaseAnimator([false, true]) { content, dimmed in
                    content.opacity(dimmed ? 0.48 : 1)
                } animation: { _ in
                    .easeInOut(duration: 1.2)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading".bSmartLocalized)
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: style == .ranking ? 0 : 16) {
            ForEach(0..<count, id: \.self) { _ in
                row
                if style == .ranking { Divider().overlay(BSmartColor.line).padding(.top, 14) }
            }
        }
    }

    @ViewBuilder private var row: some View {
        switch style {
        case .ranking:
            HStack(alignment: .top, spacing: 12) {
                BSmartSkeletonBar(width: 34, height: 26)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 9) {
                        BSmartSkeletonBar(width: 34, height: 34, circular: true)
                        VStack(alignment: .leading, spacing: 6) {
                            BSmartSkeletonBar(width: 132, height: 13)
                            BSmartSkeletonBar(width: 76, height: 9)
                        }
                        Spacer()
                        BSmartSkeletonBar(width: 58, height: 21)
                    }
                    BSmartSkeletonBar(width: 72, height: 14)
                    BSmartSkeletonBar(height: 12)
                    BSmartSkeletonBar(width: 190, height: 12)
                }
            }.padding(.vertical, 14)
        case .feed:
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 10) {
                    BSmartSkeletonBar(width: 42, height: 42, circular: true)
                    VStack(alignment: .leading, spacing: 6) {
                        BSmartSkeletonBar(width: 146, height: 14)
                        BSmartSkeletonBar(width: 90, height: 10)
                    }
                    Spacer()
                }
                BSmartSkeletonBar(width: 96, height: 18)
                BSmartSkeletonBar(height: 12)
                BSmartSkeletonBar(width: 215, height: 12)
            }.padding(.vertical, 14)
        case .chat:
            HStack(spacing: 12) {
                BSmartSkeletonBar(width: 44, height: 44, circular: true)
                VStack(alignment: .leading, spacing: 8) {
                    BSmartSkeletonBar(width: 132, height: 13)
                    BSmartSkeletonBar(width: 202, height: 12)
                }
                Spacer(minLength: 0)
            }.frame(minHeight: 58)
        case .profile:
            VStack(alignment: .leading, spacing: 16) {
                BSmartSkeletonBar(width: 72, height: 72, circular: true)
                BSmartSkeletonBar(width: 190, height: 24)
                BSmartSkeletonBar(width: 110, height: 13)
                HStack {
                    BSmartSkeletonBar(width: 122, height: 34)
                    Spacer()
                    BSmartSkeletonBar(width: 122, height: 34)
                }
            }.padding(.vertical, 14)
        case .simple:
            HStack(spacing: 12) {
                BSmartSkeletonBar(width: 36, height: 36, circular: true)
                VStack(alignment: .leading, spacing: 8) {
                    BSmartSkeletonBar(width: 156, height: 13)
                    BSmartSkeletonBar(width: 94, height: 10)
                }
                Spacer(minLength: 0)
            }.frame(minHeight: 52)
        }
    }
}

struct BSmartWordmark: View {
    var fontSize: CGFloat = 24

    var body: some View {
        Image("BSmartWordmark")
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: fontSize * 4.1, height: fontSize)
            .accessibilityLabel("bSmart")
    }
}

struct BSmartSmartMoneyAvatar: View {
    let identity: SmartMoneyPublicIdentity
    var size: CGFloat = 40

    private var assetName: String {
        let names = [
            "SmartMoneyBorderCollie",
            "SmartMoneyBorderCollieGlasses",
            "SmartMoneyBorderCollieBowTie",
            "SmartMoneyBorderCollieBandana",
            "SmartMoneyBorderCollieCap",
            "SmartMoneyBorderCollieBrown",
        ]
        return names[(identity.avatarVariant - 1) % names.count]
    }

    private var accent: Color {
        let colors = [
            BSmartColor.brand,
            BSmartColor.sky,
            BSmartColor.gold,
            BSmartColor.orange,
            BSmartColor.pulse,
            BSmartColor.electric,
            BSmartColor.violet,
            BSmartColor.pink,
            BSmartColor.cyan,
        ]
        let colorIndex = ((identity.avatarVariant - 1) / 6) % colors.count
        return colors[colorIndex]
    }

    var body: some View {
        Image(assetName)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay {
                Circle().stroke(accent, lineWidth: max(1.5, size * 0.065))
            }
            .accessibilityLabel("%@ · Anonymous capital account".bSmartLocalized(identity.displayName))
    }
}

struct BSmartPageTitle: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    @State private var showsHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !eyebrow.isEmpty {
                Text(eyebrow.bSmartLocalized.uppercased())
                    .font(.system(size: 10, weight: .black))
                    .tracking(1.15)
                    .foregroundStyle(BSmartColor.pulse)
                    .accessibilityLabel(eyebrow.bSmartLocalized)
            }
            HStack(spacing: BSmartSpacing.small) {
                Text(title.bSmartLocalized)
                    .font(.system(.title2, design: .rounded, weight: .black))
                    .foregroundStyle(BSmartColor.primaryText)
                BSmartHelpButton {
                    showsHelp = true
                }
            }
        }
        .sheet(isPresented: $showsHelp) {
            BSmartHelpSheet(title: title, message: subtitle)
        }
    }
}

struct BSmartHelpButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "questionmark.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BSmartColor.tertiaryText)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More information".bSmartLocalized)
    }
}

struct BSmartHelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let message: String

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(message.bSmartLocalized)
                    .font(.body)
                    .foregroundStyle(BSmartColor.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(BSmartSpacing.large)
            }
            .background(BSmartColor.surface)
            .navigationTitle(title.bSmartLocalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done".bSmartLocalized) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

struct BSmartIconButton: View {
    let symbol: String
    let accessibilityLabel: String
    var color: Color = BSmartColor.primaryText
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(BSmartColor.surface)
                .clipShape(Circle())
                .overlay {
                    Circle().stroke(BSmartColor.line, lineWidth: 0.75)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel.bSmartLocalized)
    }
}

struct BSmartSectionTitle: View {
    let title: String
    var detail: String?
    @State private var showsHelp = false

    private var explanatoryDetail: Bool {
        guard let detail else { return false }
        let normalized = detail.lowercased()
        return ["newest", "ranked", "only", "based", "derived", "qualified", "top "].contains {
            normalized.contains($0)
        }
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: BSmartSpacing.medium) {
            Text(title.bSmartLocalized)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(BSmartColor.primaryText)
            Spacer()
            if explanatoryDetail {
                BSmartHelpButton { showsHelp = true }
            } else if let detail {
                Text(detail.bSmartLocalized)
                    .font(.caption2)
                    .foregroundStyle(BSmartColor.tertiaryText)
                    .lineLimit(1)
            }
        }
        .sheet(isPresented: $showsHelp) {
            if let detail {
                BSmartHelpSheet(title: title, message: detail)
            }
        }
    }
}

struct BSmartStripMetric: Identifiable {
    let id: String
    let label: String
    let value: String
    var color: Color = BSmartColor.primaryText
}

struct BSmartMetricStrip: View {
    let metrics: [BSmartStripMetric]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                if index > 0 {
                    Rectangle()
                        .fill(BSmartColor.line)
                        .frame(width: 0.5)
                        .padding(.vertical, BSmartSpacing.small)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(metric.label.bSmartLocalized)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(BSmartColor.tertiaryText)
                        .lineLimit(1)
                    Text(metric.value.bSmartLocalized)
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(metric.color)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, BSmartSpacing.small)
                .padding(.vertical, 10)
            }
        }
        .background(BSmartColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                .stroke(BSmartColor.line, lineWidth: 0.6)
        }
    }
}

struct BSmartEvidenceStateCell: View {
    let title: String
    let symbol: String
    let value: String
    let detail: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.small) {
            HStack {
                Text(title.bSmartLocalized.uppercased())
                    .font(.system(size: 9, weight: .black))
                    .tracking(0.55)
                    .foregroundStyle(BSmartColor.tertiaryText)
                    .accessibilityLabel(title.bSmartLocalized)
                Spacer()
                Image(systemName: symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color)
            }
            Text(value.bSmartLocalized)
                .font(.headline.weight(.bold))
                .foregroundStyle(color)
                .lineLimit(2)
            Text(detail.bSmartLocalized)
                .font(.caption2)
                .foregroundStyle(BSmartColor.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 94, alignment: .topLeading)
        .bSmartPanel(padding: BSmartSpacing.medium)
    }
}

struct BSmartSectionHeader: View {
    let title: String
    var detail: String?
    @State private var showsHelp = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            titleText
            Spacer()
            if detail != nil {
                BSmartHelpButton { showsHelp = true }
            }
        }
        .sheet(isPresented: $showsHelp) {
            if let detail {
                BSmartHelpSheet(title: title, message: detail)
            }
        }
    }

    private var titleText: some View {
        Text(title.bSmartLocalized)
            .font(.headline)
            .foregroundStyle(BSmartColor.primaryText)
    }

}

struct BSmartAssetMark: View {
    let ticker: String
    var size: CGFloat = 44
    var contentInset: CGFloat? = nil
    var isCrypto: Bool? = nil

    private var normalizedTicker: String {
        ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    var usesCryptoLogo: Bool {
        if let isCrypto { return isCrypto }
        return UIImage(named: "Ticker_\(normalizedTicker)") == nil
            && UIImage(named: "Crypto_\(normalizedTicker)") != nil
    }

    private var hasBundledLogo: Bool {
        UIImage(named: assetName) != nil
    }

    private var assetName: String {
        "\(usesCryptoLogo ? "Crypto" : "Ticker")_\(normalizedTicker)"
    }

    private var bundledLogoInset: CGFloat {
        switch normalizedTicker {
        case "AAOI": 0.18
        case "PLTR": 0.21
        case "HOOD", "TSLA": 0.15
        case "NVDA": 0.11
        case "AVGO", "MSTR": 0.07
        default: 0
        }
    }

    private var remoteLogoURL: URL? {
        guard !usesCryptoLogo, !nonEquitySymbols.contains(normalizedTicker),
              let escapedTicker = normalizedTicker.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        return URL(string: "https://financialmodelingprep.com/image-stock/\(escapedTicker).png")
    }

    private var nonEquitySymbols: Set<String> {
        ["SP500", "USTECH", "XYZ100", "JP225", "GOLD", "SILVER", "COPPER", "BRENTOIL", "CL", "JPY"]
    }

    private var fallbackSymbol: String {
        if usesCryptoLogo { return "hexagon.fill" }
        return switch normalizedTicker {
        case "GOLD", "SILVER", "COPPER": "mountain.2.fill"
        case "BRENTOIL", "CL": "drop.fill"
        case "JPY": "yensign.circle.fill"
        case "SP500", "USTECH", "XYZ100", "JP225": "chart.line.uptrend.xyaxis"
        default: "building.2.fill"
        }
    }

    private var color: Color {
        if usesCryptoLogo { return BSmartColor.secondaryText }
        let value = ticker.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let palette = [BSmartColor.brand, BSmartColor.sky, BSmartColor.gold, BSmartColor.orange]
        return palette[value % palette.count]
    }

    var body: some View {
        Group {
            if hasBundledLogo {
                bundledLogo
            } else if let remoteLogoURL {
                AsyncImage(url: remoteLogoURL, transaction: Transaction(animation: .easeOut(duration: 0.18))) { phase in
                    if case let .success(image) = phase {
                        logoImage(image, inset: 0)
                    } else {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("%@ asset".bSmartLocalized(ticker))
    }

    @ViewBuilder
    private var bundledLogo: some View {
        if usesCryptoLogo {
            logoImage(Image(assetName).renderingMode(.original), inset: normalizedTicker == "HYPE" ? 0.12 : 0)
                .background(cryptoLogoBackground)
                .clipShape(Circle())
        } else if TickerLogoRegistry.templateSymbols.contains(normalizedTicker) {
            logoImage(
                Image("Ticker_\(normalizedTicker)").renderingMode(.template),
                inset: bundledLogoInset
            )
            .foregroundStyle(BSmartColor.primaryText)
        } else {
            logoImage(Image("Ticker_\(normalizedTicker)"), inset: bundledLogoInset)
        }
    }

    private var cryptoLogoBackground: Color {
        // Match the official coin renderer's backing colors for transparent marks.
        switch normalizedTicker {
        case "2Z", "ETC", "ETH", "UNIBOT", "BIGTIME", "NEAR", "ADA", "ONDO",
             "DYM", "AR", "XRP", "WLD", "CFX", "GALA", "XLM", "MEGA":
            return .white
        case "FET": return Color(red: 32 / 255, green: 41 / 255, blue: 68 / 255)
        case "ZEN": return Color(red: 3 / 255, green: 24 / 255, blue: 65 / 255)
        case "HYPE": return Color(red: 6 / 255, green: 42 / 255, blue: 37 / 255)
        default: return Color(red: 15 / 255, green: 26 / 255, blue: 31 / 255)
        }
    }

    private func logoImage(_ image: Image, inset: CGFloat) -> some View {
        image
            .resizable()
            .scaledToFit()
            .padding(size * (contentInset ?? inset))
    }

    private var fallback: some View {
        Group {
            if usesCryptoLogo {
                Text(String(normalizedTicker.prefix(3)))
                    .font(.system(size: size * 0.23, weight: .semibold))
            } else {
                Image(systemName: fallbackSymbol)
            }
        }
            .font(.system(size: size * 0.34, weight: .bold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: min(8, size * 0.18), style: .continuous))
    }
}

struct BSmartAvatar: View {
    let url: URL?
    let name: String
    var size: CGFloat = 40
    var fallbackColor: Color = BSmartColor.sky
    var fallbackSymbol: String? = nil
    @Environment(\.scenePhase) private var scenePhase
    @State private var loadedImage: AvatarImage?

    private var imageURL: URL? { url ?? RedditAuthorAvatars.url(forDisplayName: name) }

    var body: some View {
        Group {
            if let asset = AuthorAvatarAsset.name(for: imageURL) {
                Image(asset).resizable().scaledToFill()
            } else if let loadedImage, loadedImage.sourceURL == imageURL {
                Image(uiImage: loadedImage.image).resizable().scaledToFill()
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle().stroke(BSmartColor.line, lineWidth: 0.75)
        }
        .accessibilityLabel("%@ avatar".bSmartLocalized(name))
        .task(id: RequestKey(url: imageURL, isActive: scenePhase == .active)) {
            guard scenePhase == .active, let url = imageURL, AuthorAvatarAsset.name(for: url) == nil else { return }
            let result = await AvatarImageStore.shared.image(for: url)
            guard !Task.isCancelled else { return }
            loadedImage = result
        }
    }

    private struct RequestKey: Hashable {
        let url: URL?
        let isActive: Bool
    }

    private var fallback: some View {
        Group {
            if let fallbackSymbol {
                Image(systemName: fallbackSymbol)
            } else {
                Text(String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased())
            }
        }
            .font(.system(size: size * 0.34, weight: .black, design: .rounded))
            .foregroundStyle(fallbackColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(fallbackColor.opacity(0.12))
    }
}

struct BSmartStatusPill: View {
    let text: String
    var symbol: String?
    var color: Color = BSmartColor.brand

    var body: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.caption2.weight(.bold))
            }
            Text(text.bSmartLocalized)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, BSmartSpacing.small)
        .frame(height: 28)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous)
                .stroke(color.opacity(0.32), lineWidth: 0.5)
        }
    }
}

struct BSmartMetric: View {
    let label: String
    let value: String
    var change: String?
    var changeColor: Color = BSmartColor.brand

    var body: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.xSmall) {
            Text(label.bSmartLocalized)
                .font(.caption)
                .foregroundStyle(BSmartColor.secondaryText)
            HStack(alignment: .firstTextBaseline, spacing: BSmartSpacing.small) {
                Text(value)
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                if let change {
                    Text(change)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(changeColor)
                        .monospacedDigit()
                }
            }
        }
    }
}

struct BSmartTag: View {
    let text: String
    var color: Color = BSmartColor.secondaryText

    var body: some View {
        Text(text.bSmartLocalized)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous)
                    .stroke(color.opacity(0.35), lineWidth: 0.5)
            }
    }
}

struct BSmartLoadingView: View {
    var body: some View {
        VStack(spacing: BSmartSpacing.medium) {
            ProgressView()
                .tint(BSmartColor.brand)
            Text("Loading bSmart".bSmartLocalized)
                .font(.subheadline)
                .foregroundStyle(BSmartColor.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("app.loading")
        .bSmartPage()
    }
}

struct BSmartErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Unable to load bSmart", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try again", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .accessibilityIdentifier("app.error")
        .bSmartPage()
    }
}

extension SignalPriority {
    var color: Color {
        switch self {
        case .critical: BSmartColor.bear
        case .important: BSmartColor.gold
        case .notable: BSmartColor.brand
        }
    }

    var symbol: String {
        switch self {
        case .critical: "exclamationmark.triangle.fill"
        case .important: "bolt.fill"
        case .notable: "circle.fill"
        }
    }
}

extension PersonalizedAttentionLevel {
    var color: Color {
        switch self {
        case .priority: BSmartColor.bear
        case .review: BSmartColor.gold
        case .monitor: BSmartColor.brand
        }
    }

    var symbol: String {
        switch self {
        case .priority: "exclamationmark.triangle.fill"
        case .review: "eye.fill"
        case .monitor: "waveform.path.ecg"
        }
    }
}

extension SignalDirection {
    var color: Color {
        switch self {
        case .bullish: BSmartColor.bull
        case .neutral: BSmartColor.secondaryText
        case .bearish: BSmartColor.bear
        case .mixed: BSmartColor.gold
        }
    }
}

extension SignalDataStatus {
    var color: Color {
        switch self {
        case .current: BSmartColor.brand
        case .delayed: BSmartColor.gold
        }
    }

    var symbol: String {
        switch self {
        case .current: "checkmark.circle"
        case .delayed: "clock.badge.exclamationmark"
        }
    }
}

// Legacy styling for the deprecated InvestmentEvent contract.
extension EventSeverity {
    var color: Color {
        switch self {
        case .critical: BSmartColor.bear
        case .important: BSmartColor.gold
        case .notable: BSmartColor.brand
        }
    }

    var symbol: String {
        switch self {
        case .critical: "exclamationmark.triangle.fill"
        case .important: "bolt.fill"
        case .notable: "circle.fill"
        }
    }
}

extension SmartMoneyCoverage {
    var color: Color {
        switch self {
        case .available: BSmartColor.brand
        case .unavailable: BSmartColor.gold
        }
    }

    var symbol: String {
        switch self {
        case .available: "checkmark.shield"
        case .unavailable: "questionmark.diamond"
        }
    }
}

extension FormatStyle where Self == FloatingPointFormatStyle<Double>.Currency {
    static var usd: Self { .bSmartDollars }
}
