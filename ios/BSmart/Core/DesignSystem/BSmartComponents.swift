import SwiftUI

struct BSmartWordmark: View {
    var fontSize: CGFloat = 24

    var body: some View {
        Text("bSmart")
            .font(.system(size: fontSize, weight: .bold, design: .default))
            .foregroundStyle(BSmartColor.brand)
            .accessibilityLabel("bSmart")
    }
}

struct BSmartSmartMoneyAvatar: View {
    let identity: SmartMoneyPublicIdentity
    var size: CGFloat = 40

    private var accent: Color {
        let colors = [
            BSmartColor.brand,
            BSmartColor.sky,
            BSmartColor.gold,
            BSmartColor.orange,
            BSmartColor.pulse,
            BSmartColor.electric,
        ]
        return colors[(identity.avatarVariant - 1) % colors.count]
    }

    var body: some View {
        Image("SmartMoneyBorderCollie")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay {
                Circle().stroke(accent.opacity(0.82), lineWidth: max(1, size * 0.045))
            }
            .accessibilityLabel("%@ · Anonymous capital account".bSmartLocalized(identity.displayName))
    }
}

struct BSmartPageTitle: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(eyebrow.bSmartLocalized.uppercased())
                .font(.system(size: 10, weight: .black))
                .tracking(1.15)
                .foregroundStyle(BSmartColor.pulse)
                .accessibilityLabel(eyebrow.bSmartLocalized)
            Text(title.bSmartLocalized)
                .font(.system(.title2, design: .rounded, weight: .black))
                .foregroundStyle(BSmartColor.primaryText)
            Text(subtitle.bSmartLocalized)
                .font(.caption)
                .foregroundStyle(BSmartColor.secondaryText)
                .lineLimit(2)
        }
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
                .frame(width: 38, height: 38)
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

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: BSmartSpacing.medium) {
            Text(title.bSmartLocalized)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(BSmartColor.primaryText)
            Spacer()
            if let detail {
                Text(detail.bSmartLocalized)
                    .font(.caption2)
                    .foregroundStyle(BSmartColor.tertiaryText)
                    .lineLimit(1)
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

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                titleText
                Spacer()
                detailText
            }
            VStack(alignment: .leading, spacing: BSmartSpacing.xSmall) {
                titleText
                detailText
            }
        }
    }

    private var titleText: some View {
        Text(title.bSmartLocalized)
            .font(.headline)
            .foregroundStyle(BSmartColor.primaryText)
    }

    @ViewBuilder
    private var detailText: some View {
        if let detail {
            Text(detail.bSmartLocalized)
                .font(.caption)
                .foregroundStyle(BSmartColor.tertiaryText)
        }
    }
}

struct BSmartAssetMark: View {
    let ticker: String
    var size: CGFloat = 44

    private var normalizedTicker: String {
        ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private var bundledTickers: Set<String> {
        ["AVGO", "HOOD", "MSTR", "NVDA", "PLTR"]
    }

    private var remoteLogoURL: URL? {
        guard !nonEquitySymbols.contains(normalizedTicker),
              let escapedTicker = normalizedTicker.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        return URL(string: "https://financialmodelingprep.com/image-stock/\(escapedTicker).png")
    }

    private var nonEquitySymbols: Set<String> {
        ["SP500", "USTECH", "XYZ100", "JP225", "SPCX", "SKHX", "GOLD", "SILVER", "COPPER", "BRENTOIL", "CL", "JPY"]
    }

    private var fallbackSymbol: String {
        switch normalizedTicker {
        case "GOLD", "SILVER", "COPPER": "mountain.2.fill"
        case "BRENTOIL", "CL": "drop.fill"
        case "JPY": "yensign.circle.fill"
        case "SP500", "USTECH", "XYZ100", "JP225", "SPCX", "SKHX": "chart.line.uptrend.xyaxis"
        default: "building.2.fill"
        }
    }

    private var color: Color {
        let value = ticker.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let palette = [BSmartColor.brand, BSmartColor.sky, BSmartColor.gold, BSmartColor.orange]
        return palette[value % palette.count]
    }

    var body: some View {
        Group {
            if bundledTickers.contains(normalizedTicker) {
                logoImage(Image("Ticker_\(normalizedTicker)"))
            } else if let remoteLogoURL {
                AsyncImage(url: remoteLogoURL, transaction: Transaction(animation: .easeOut(duration: 0.18))) { phase in
                    if case let .success(image) = phase {
                        logoImage(image)
                    } else {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: min(8, size * 0.18), style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: min(8, size * 0.18), style: .continuous)
                .stroke(BSmartColor.line, lineWidth: 0.75)
        }
        .accessibilityLabel("%@ asset".bSmartLocalized(ticker))
    }

    private func logoImage(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFit()
            .padding(size * 0.12)
    }

    private var fallback: some View {
        Image(systemName: fallbackSymbol)
            .font(.system(size: size * 0.34, weight: .bold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(color.opacity(0.1))
    }
}

struct BSmartAvatar: View {
    let url: URL?
    let name: String
    var size: CGFloat = 40
    var fallbackColor: Color = BSmartColor.sky

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallback
                    }
                }
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
    }

    private var fallback: some View {
        Text(String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased())
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
            .background(color.opacity(0.08))
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
            Text("Loading your portfolio")
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
        case .bullish: BSmartColor.brand
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
    static var usd: Self { .currency(code: "USD") }
}
