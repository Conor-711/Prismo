import Charts
import SwiftUI
import WebKit

enum HyperliquidTradingPresentation {
    case full
    case quick
}

struct HyperliquidTradingView: View {
    @Environment(\.opinionTradeSource) private var opinionSource
    @EnvironmentObject private var trading: HyperliquidTradingStore
    let symbol: String
    let initialSide: PaperTradeSide
    let presentation: HyperliquidTradingPresentation
    var activities: [TickerSmartActivityItem]? = nil
    private let initialCoin: String?
    private let initialAmount: String
    private let initialReduction: Bool

    @State private var showsMarketPicker = false
    @State private var marketLoadAttempt = 0
    @State private var quickOrderReady = false

    init(
        ticker: TickerIntelligence,
        initialSide: PaperTradeSide = .long,
        presentation: HyperliquidTradingPresentation = .full
    ) {
        self.init(symbol: ticker.ticker, initialSide: initialSide, presentation: presentation)
    }

    init(
        symbol: String,
        initialSide: PaperTradeSide = .long,
        presentation: HyperliquidTradingPresentation = .full,
        activities: [TickerSmartActivityItem]? = nil,
        initialCoin: String? = nil, initialAmount: String = "", initialReduction: Bool = false
    ) {
        self.symbol = symbol.uppercased()
        self.initialSide = initialSide
        self.presentation = presentation
        self.activities = activities
        self.initialCoin = initialCoin; self.initialAmount = initialAmount; self.initialReduction = initialReduction
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let market = trading.activeMarket {
                if presentation == .quick {
                    ZStack(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 24) {
                            if quickOrderReady {
                                marketIdentity(market).frame(height: 52)
                            } else {
                                Color.clear.frame(height: 52)
                            }
                            LiveMarketOrderDestination(coin: market.coin, dex: market.dex,
                                                       side: initialSide == .long ? .buy : .sell,
                                                       initialAmount: initialAmount, initialReduction: initialReduction,
                                                       market: market,
                                                       opinionSource: opinionSource?.matches(symbol: market.symbol) == true
                                                           ? opinionSource : nil,
                                                       onReady: { quickOrderReady = true })
                                .id(market.coin)
                        }
                        .opacity(quickOrderReady ? 1 : 0)
                        .allowsHitTesting(quickOrderReady)
                        .accessibilityHidden(!quickOrderReady)
                        if !quickOrderReady {
                            HyperliquidTradeLoadingView(symbol: symbol, presentation: .quick,
                                                        reducing: initialReduction,
                                                        isCrypto: market.dex.isEmpty)
                                .background(BSmartColor.ink)
                                .transition(.identity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    HyperliquidMarketChart(market: market, activities: activities)
                }
            } else if trading.isLoadingMarket || trading.errorMessage == nil {
                HyperliquidTradeLoadingView(symbol: symbol, presentation: presentation,
                                            reducing: initialReduction, chartRange: trading.chartRange,
                                            isCrypto: initialCoin.map { !$0.contains(":") } ?? false)
                    .transition(.opacity)
            } else if trading.verifiedNoMarketSymbol == symbol && !initialReduction
                        && !ExternalTradeLinks.destinations(for: symbol).isEmpty {
                if presentation == .quick {
                    ScrollView {
                        externalVenuesContent.padding(.top, 40)
                    }
                    .scrollIndicators(.hidden)
                } else {
                    if let tradingViewSymbol = TradingViewChartSymbol.forTicker(symbol) {
                        TradingViewFallbackChart(symbol: tradingViewSymbol)
                    }
                    externalVenuesContent.padding(.top, 16)
                }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.largeTitle)
                    Text(trading.errorMessage ?? "Hyperliquid market unavailable".bSmartLocalized)
                        .multilineTextAlignment(.center)
                    Button("Retry".bSmartLocalized) { marketLoadAttempt += 1 }
                        .accessibilityIdentifier("trade.market.retry")
                    if !initialReduction {
                        Button("Choose a market".bSmartLocalized) { showsMarketPicker = true }
                    }
                }
                .foregroundStyle(BSmartColor.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 260)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: presentation == .quick ? .infinity : nil, alignment: .topLeading)
        .task(id: "\(symbol):\(marketLoadAttempt)") {
            await trading.runLiveMarket(symbol: symbol, coin: initialCoin)
        }
        .task(id: trading.chartRange) {
            await trading.reloadCandles()
        }
        .onChange(of: trading.activeMarket?.coin) { _, _ in quickOrderReady = false }
        .sheet(isPresented: $showsMarketPicker) {
            HyperliquidMarketPickerView()
                .environmentObject(trading)
        }
    }

    private var externalVenuesContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            ExternalTradingVenuesView(symbol: symbol)
            Button("Choose a market".bSmartLocalized) { showsMarketPicker = true }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BSmartColor.brand)
        }
    }

    private func marketIdentity(_ market: HyperliquidPerpMarket) -> some View {
        HStack(spacing: 12) {
            BSmartAssetMark(ticker: market.symbol, size: 44, isCrypto: market.dex.isEmpty)
            Button {
                showsMarketPicker = true
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(market.symbol)
                            .font(.system(size: 17, weight: .semibold))
                        if !initialReduction {
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.bold))
                        }
                    }
                    Text("\((market.openInterest * market.markPrice).bSmartCompactUSD) OI")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(BSmartColor.secondaryText)
                }
                .foregroundStyle(BSmartColor.primaryText)
            }
            .buttonStyle(.bSmartPlain)
            .disabled(initialReduction)
            .accessibilityIdentifier("trade.market-picker")
            Spacer(minLength: 8)
            if presentation == .quick {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(market.markPrice.bSmartMarketPrice)
                        .font(.headline).monospacedDigit()
                    Text("Market order".bSmartLocalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BSmartColor.secondaryText)
                }
                .padding(.trailing, 44)
            }
        }
    }
}

// A bare ticker can resolve to a different company or exchange on TradingView.
// Keep this list explicit until the app has authoritative exchange metadata.
enum TradingViewChartSymbol {
    private static let nasdaq: Set<String> = [
        "AAPL", "AMAT", "AMD", "AMZN", "ARM", "ASML", "AVGO", "COIN", "GOOGL",
        "HOOD", "INTC", "LCID", "MARA", "META", "MSFT", "MSTR", "MU", "NFLX",
        "NVDA", "OUST", "PLTR", "PYPL", "QCOM", "RIOT", "RIVN", "SMCI",
        "SOFI", "TSLA"
    ]
    private static let nyse: Set<String> = [
        "AMC", "BA", "BABA", "DELL", "DIS", "F", "GME", "JPM", "NIO",
        "ORCL", "PFE", "TSM", "UBER"
    ]

    static func forTicker(_ ticker: String) -> String? {
        let symbol = ticker.uppercased()
        if nasdaq.contains(symbol) { return "NASDAQ:\(symbol)" }
        if nyse.contains(symbol) { return "NYSE:\(symbol)" }
        return nil
    }
}

private struct TradingViewFallbackChart: View {
    @Environment(\.colorScheme) private var colorScheme
    let symbol: String
    @State private var loadState: TradingViewWidgetLoadState = .loading
    @State private var loadAttempt = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if loadState == .failed {
                VStack(spacing: 12) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.title2)
                    Text("TradingView chart unavailable".bSmartLocalized)
                        .font(.subheadline)
                    if let sourceURL {
                        Link(destination: sourceURL) {
                            Label("Open chart in TradingView".bSmartLocalized, systemImage: "arrow.up.right")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BSmartColor.brand)
                    }
                    Button("Retry".bSmartLocalized) {
                        loadState = .loading
                        loadAttempt += 1
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BSmartColor.brand)
                }
                .foregroundStyle(BSmartColor.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                GeometryReader { geometry in
                    ZStack {
                        TradingViewChartWebView(symbol: symbol, isDark: colorScheme == .dark) {
                            loadState = $0
                        }
                        .id(loadAttempt)
                        .frame(width: geometry.size.width, height: 445)
                        if loadState == .loading {
                            BSmartColor.ink
                                .overlay { ProgressView() }
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(width: geometry.size.width, height: 445)
                }
                .frame(height: 445)
                .accessibilityIdentifier("ticker.tradingview-chart")
                .task(id: loadAttempt) {
                    try? await Task.sleep(for: .seconds(15))
                    if !Task.isCancelled && loadState == .loading { loadState = .failed }
                }
            }
            if loadState != .failed {
                HStack(spacing: 6) {
                    if let sourceURL {
                        Link(destination: sourceURL) {
                            HStack(spacing: 4) {
                                Text("Market data by TradingView".bSmartLocalized)
                                Image(systemName: "arrow.up.right")
                            }
                        }
                    }
                    Text("· \(symbol)")
                    Spacer(minLength: 0)
                    Text("Quotes may be delayed".bSmartLocalized)
                }
                .font(.caption2)
                .foregroundStyle(BSmartColor.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sourceURL: URL? {
        URL(string: "https://www.tradingview.com/symbols/\(symbol.replacingOccurrences(of: ":", with: "-"))/")
    }
}

private enum TradingViewWidgetLoadState {
    case loading, ready, failed
}

private struct TradingViewChartWebView: UIViewRepresentable {
    let symbol: String
    let isDark: Bool
    let onStatusChange: (TradingViewWidgetLoadState) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "widgetStatus")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onStatusChange = onStatusChange
        let identity = "\(symbol):\(isDark)"
        guard context.coordinator.loadedIdentity != identity else { return }
        context.coordinator.loadedIdentity = identity
        context.coordinator.chartReady = false
        context.coordinator.framesReady = false
        context.coordinator.snapshotAttempts = 0
        context.coordinator.hasFinished = false
        context.coordinator.webView = webView
        guard let pageURL = URL(string: "https://bsmart.today/embedded/tradingview-chart") else { return }
        webView.loadSimulatedRequest(URLRequest(url: pageURL),
                                     responseHTML: Self.html(symbol: symbol, isDark: isDark))
    }

    func makeCoordinator() -> Coordinator { Coordinator(onStatusChange: onStatusChange) }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var loadedIdentity: String?
        var chartReady = false
        var framesReady = false
        var snapshotAttempts = 0
        var hasFinished = false
        weak var webView: WKWebView?
        var onStatusChange: (TradingViewWidgetLoadState) -> Void

        init(onStatusChange: @escaping (TradingViewWidgetLoadState) -> Void) {
            self.onStatusChange = onStatusChange
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let status = message.body as? String else { return }
            switch status {
            case "chart-ready": chartReady = true
            case "frames-ready": framesReady = true
            case "failed": fail()
            default: break
            }
            if chartReady && framesReady && snapshotAttempts == 0 { inspectChart() }
        }

        private func inspectChart() {
            guard !hasFinished, let webView, snapshotAttempts < 8 else { return }
            snapshotAttempts += 1
            let configuration = WKSnapshotConfiguration()
            configuration.rect = CGRect(origin: .zero, size: webView.bounds.size)
            webView.takeSnapshot(with: configuration) { [weak self] image, _ in
                guard let self, !self.hasFinished else { return }
                if let image, TradingViewChartPixelCheck.hasVisibleContent(image) {
                    self.hasFinished = true
                    self.onStatusChange(.ready)
                } else if self.snapshotAttempts == 8 {
                    self.fail()
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                        self?.inspectChart()
                    }
                }
            }
        }

        private func fail() {
            guard !hasFinished else { return }
            hasFinished = true
            onStatusChange(.failed)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url,
               url.scheme == "https" {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }

    private static func html(symbol: String, isDark: Bool) -> String {
        let theme = isDark ? "dark" : "light"
        let background = isDark ? "#111615" : "#f6f7f9"
        guard let data = try? JSONSerialization.data(withJSONObject: symbol, options: .fragmentsAllowed),
              let symbolJSON = String(data: data, encoding: .utf8) else { return "" }
        return """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>
          html,body{margin:0;padding:0;width:100%;height:445px;background:\(background);overflow:hidden}
          .tradingview-widget-container{width:100%;overflow:hidden}
        </style></head><body>
        <div class="tradingview-widget-container" style="height:445px">
          <div class="tradingview-widget-container__widget" style="height:100%;width:100%"></div>
          <script src="https://s3.tradingview.com/external-embedding/embed-widget-advanced-chart.js" async
                  onload="window.webkit.messageHandlers.widgetStatus.postMessage('chart-ready')"
                  onerror="window.webkit.messageHandlers.widgetStatus.postMessage('failed')">
          {"autosize":true,"symbol":\(symbolJSON),"interval":"D","timezone":"Etc/UTC","theme":"\(theme)","style":"1","locale":"en","isTransparent":true,"allow_symbol_change":false,"hide_top_toolbar":false,"hide_side_toolbar":true,"save_image":false,"calendar":false,"support_host":"https://www.tradingview.com"}
          </script>
        </div>
        <script>
          const readiness = setInterval(() => {
            const widgets = [...document.querySelectorAll('.tradingview-widget-container')];
            if (widgets.length !== 1 || !widgets.every(widget =>
              [...widget.querySelectorAll('iframe')].some(frame => {
                const bounds = frame.getBoundingClientRect();
                return bounds.width > 100 && bounds.height > 80;
              })
            )) return;
            clearInterval(readiness);
            window.webkit.messageHandlers.widgetStatus.postMessage('frames-ready');
          }, 250);
        </script></body></html>
        """
    }
}

enum TradingViewChartPixelCheck {
    static func hasVisibleContent(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }
        let side = 64
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        return pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            var visiblePixels = 0
            let samples = bytes.bindMemory(to: UInt8.self)
            let background = (samples[0], samples[1], samples[2])
            for index in stride(from: 0, to: samples.count, by: 4) {
                if abs(Int(samples[index]) - Int(background.0)) > 35
                    || abs(Int(samples[index + 1]) - Int(background.1)) > 35
                    || abs(Int(samples[index + 2]) - Int(background.2)) > 35 {
                    visiblePixels += 1
                }
            }
            return visiblePixels >= 12
        }
    }
}


struct HyperliquidMarketPickerView: View {
    @EnvironmentObject private var trading: HyperliquidTradingStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filteredMarkets: [HyperliquidPerpMarket] {
        guard !query.isEmpty else { return trading.marketCatalog }
        return trading.marketCatalog.filter {
            $0.symbol.localizedCaseInsensitiveContains(query)
                || $0.coin.localizedCaseInsensitiveContains(query)
                || $0.dexDisplayName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if trading.isLoadingCatalog && trading.marketCatalog.isEmpty {
                    ForEach(0..<8, id: \.self) { _ in
                        BSmartSkeletonRows(style: .simple, count: 1)
                            .listRowBackground(BSmartColor.ink)
                    }
                } else {
                    ForEach(filteredMarkets) { market in
                        Button {
                            Task {
                                await trading.selectMarket(market)
                                dismiss()
                            }
                        } label: {
                            HStack(spacing: BSmartSpacing.medium) {
                                BSmartAssetMark(ticker: market.symbol, size: 36, isCrypto: market.dex.isEmpty)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(market.symbol)
                                        .font(.subheadline.weight(.black))
                                        .foregroundStyle(BSmartColor.primaryText)
                                    Text("\(market.maxLeverage)x")
                                        .font(.caption2)
                                        .foregroundStyle(BSmartColor.tertiaryText)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text(market.markPrice.bSmartMarketPrice)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(BSmartColor.primaryText)
                                        .monospacedDigit()
                                    Text(market.dayChangePercent.formatted(
                                        .percent.precision(.fractionLength(2)).sign(strategy: .always())
                                    ))
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(market.dayChangePercent >= 0 ? BSmartColor.bull : BSmartColor.bear)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.bSmartPlain)
                        .listRowBackground(BSmartColor.surface)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(BSmartColor.ink)
            .bSmartSearchable(text: $query, prompt: "Market or symbol".bSmartLocalized)
            .navigationTitle("Hyperliquid markets".bSmartLocalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Group {
                    Button("Done".bSmartLocalized) { dismiss() }
                }.buttonStyle(.bSmartToolbar) }.bSmartHideSystemBackground()
            }
            .task {
                await trading.loadFullCatalog()
            }
        }
        .bSmartPage()
    }
}
