import SwiftUI

struct BrokerageConnectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    var autoDismissAfterConnection = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: BSmartSpacing.xLarge) {
                    intro

                    if !model.linkedBrokerageAccounts.isEmpty {
                        BSmartSectionHeader(
                            title: "Linked accounts",
                            detail: "%d connected".bSmartLocalized(model.linkedBrokerageAccounts.count)
                        )

                        ForEach(model.linkedBrokerageAccounts) { account in
                            BSmartDetailNavigationLink(id: "linked-brokerage-\(account.id)") {
                                BrokerageProviderSetupView(
                                    provider: account.provider,
                                    onConnected: autoDismissAfterConnection ? { dismiss() } : nil
                                )
                            } label: {
                                linkedAccountRow(account)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    BSmartSectionHeader(
                        title: "Available providers",
                        detail: "Read-only access"
                    )

                    ForEach(BrokerageProvider.allCases) { provider in
                        BSmartDetailNavigationLink(id: "brokerage-provider-\(provider.rawValue)") {
                            BrokerageProviderSetupView(
                                provider: provider,
                                onConnected: autoDismissAfterConnection ? { dismiss() } : nil
                            )
                        } label: {
                            providerRow(provider)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("brokerage.provider.\(provider.rawValue)")
                    }

                    prototypeNotice
                }
                .padding(BSmartSpacing.large)
                .padding(.bottom, BSmartSpacing.xLarge)
            }
            .background(BSmartColor.ink)
            .navigationTitle("Brokerage connections".bSmartLocalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done".bSmartLocalized) { dismiss() }
                }
            }
        }
        .bSmartPage()
        .accessibilityIdentifier("brokerage-connections.screen")
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            HStack(spacing: BSmartSpacing.medium) {
                Image(systemName: "link.badge.plus")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(BSmartColor.brand)
                    .frame(width: 44, height: 44)
                    .background(BSmartColor.brand.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Bring in your real portfolio".bSmartLocalized)
                        .font(.headline.weight(.bold))
                    Text("Use positions and cost basis to personalize every event.".bSmartLocalized)
                        .font(.caption)
                        .foregroundStyle(BSmartColor.secondaryText)
                }
            }

            HStack(spacing: BSmartSpacing.small) {
                Label("Positions", systemImage: "chart.pie.fill")
                Label("Balances", systemImage: "dollarsign.circle.fill")
                Label("Read-only", systemImage: "lock.shield.fill")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(BSmartColor.secondaryText)
        }
    }

    private func linkedAccountRow(_ account: LinkedBrokerageAccount) -> some View {
        HStack(spacing: BSmartSpacing.medium) {
            BrokerageProviderBadge(provider: account.provider, size: 42)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: BSmartSpacing.small) {
                    Text(account.provider.displayName)
                        .font(.subheadline.weight(.bold))
                    Text("PROTOTYPE".bSmartLocalized)
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(BSmartColor.pulseInk)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(BSmartColor.pulse)
                        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control))
                }
                Text("Synced %@".bSmartLocalized(account.lastSyncedAt.bSmartRelativeTimestamp))
                    .font(.caption)
                    .foregroundStyle(BSmartColor.secondaryText)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(BSmartColor.brand)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(BSmartColor.tertiaryText)
        }
        .bSmartSurface(padding: BSmartSpacing.medium)
    }

    private func providerRow(_ provider: BrokerageProvider) -> some View {
        HStack(spacing: BSmartSpacing.medium) {
            BrokerageProviderBadge(provider: provider, size: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(provider.displayName)
                    .font(.subheadline.weight(.bold))
                Text(provider.coverageDescription.bSmartLocalized)
                    .font(.caption)
                    .foregroundStyle(BSmartColor.secondaryText)
            }
            Spacer()
            if model.linkedBrokerageAccount(for: provider) != nil {
                Text("Linked".bSmartLocalized)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(BSmartColor.brand)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(BSmartColor.tertiaryText)
        }
        .bSmartSurface(padding: BSmartSpacing.medium)
    }

    private var prototypeNotice: some View {
        Label {
            Text("Prototype only. This build never contacts a brokerage and never collects account credentials.".bSmartLocalized)
        } icon: {
            Image(systemName: "hammer.fill")
                .foregroundStyle(BSmartColor.gold)
        }
        .font(.caption)
        .foregroundStyle(BSmartColor.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, BSmartSpacing.xSmall)
    }
}

private struct BrokerageProviderSetupView: View {
    @EnvironmentObject private var model: AppModel
    let provider: BrokerageProvider
    let onConnected: (() -> Void)?

    @State private var isAuthorizing = false
    @State private var isReviewingHoldings = false
    @State private var isConfirmingDisconnect = false
    @State private var selectedTickers: Set<String>

    init(provider: BrokerageProvider, onConnected: (() -> Void)? = nil) {
        self.provider = provider
        self.onConnected = onConnected
        _selectedTickers = State(initialValue: Set(
            provider.previewHoldings.filter(\.isSupported).map(\.ticker)
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BSmartSpacing.xLarge) {
                providerHeader

                if let account = model.linkedBrokerageAccount(for: provider) {
                    connectedContent(account)
                } else if isReviewingHoldings {
                    holdingsReview
                } else {
                    authorizationContent
                }
            }
            .padding(BSmartSpacing.large)
            .padding(.bottom, BSmartSpacing.xLarge)
        }
        .background(BSmartColor.ink)
        .navigationTitle(provider.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Disconnect %@?".bSmartLocalized(provider.displayName),
            isPresented: $isConfirmingDisconnect,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                model.disconnectBrokerage(provider)
                isReviewingHoldings = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Imported positions stay in your portfolio until you remove them.".bSmartLocalized)
        }
        .accessibilityIdentifier("brokerage-setup.\(provider.rawValue)")
    }

    private var providerHeader: some View {
        HStack(spacing: BSmartSpacing.medium) {
            BrokerageProviderBadge(provider: provider, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(provider.displayName)
                    .font(.title3.weight(.bold))
                Text(provider.coverageDescription.bSmartLocalized)
                    .font(.caption)
                    .foregroundStyle(BSmartColor.secondaryText)
            }
            Spacer()
        }
    }

    private var authorizationContent: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.xLarge) {
            VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
                BSmartSectionHeader(title: "Read-only permissions", detail: provider.authorizationMethod)
                permissionRow("View current positions", symbol: "chart.pie.fill")
                permissionRow("View balances and cost basis", symbol: "dollarsign.circle.fill")
                permissionRow("Refresh holdings when you open bSmart", symbol: "arrow.clockwise")
                Divider().overlay(BSmartColor.line)
                permissionRow("Cannot place trades or withdraw funds", symbol: "lock.shield.fill", color: BSmartColor.brand)
            }
            .bSmartSurface()

            Label {
                Text("No credentials are requested or stored in this prototype.".bSmartLocalized)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(BSmartColor.gold)
            }
            .font(.caption)
            .foregroundStyle(BSmartColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)

            Button {
                previewAuthorization()
            } label: {
                HStack {
                    if isAuthorizing {
                        ProgressView()
                            .tint(BSmartColor.pulseInk)
                    } else {
                        Image(systemName: "lock.open.fill")
                    }
                    Text((isAuthorizing ? "Opening secure authorization" : "Preview secure connection").bSmartLocalized)
                    Spacer()
                    if !isAuthorizing {
                        Image(systemName: "arrow.right")
                    }
                }
                .font(.headline)
                .foregroundStyle(BSmartColor.pulseInk)
                .padding(.horizontal, BSmartSpacing.large)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(BSmartColor.brand)
                .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isAuthorizing)
            .accessibilityIdentifier("brokerage.preview-authorization")
        }
    }

    private var holdingsReview: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.xLarge) {
            VStack(alignment: .leading, spacing: BSmartSpacing.xSmall) {
                Label("Authorization preview complete", systemImage: "checkmark.shield.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(BSmartColor.brand)
                Text("Review the sample holdings that a read-only connection would return.".bSmartLocalized)
                    .font(.caption)
                    .foregroundStyle(BSmartColor.secondaryText)
            }

            BSmartSectionHeader(
                title: "Detected holdings",
                detail: "%d assets".bSmartLocalized(provider.previewHoldings.count)
            )

            VStack(spacing: 0) {
                ForEach(Array(provider.previewHoldings.enumerated()), id: \.element.id) { index, holding in
                    if index > 0 {
                        Divider().overlay(BSmartColor.line)
                    }
                    holdingRow(holding)
                }
            }
            .bSmartSurface(padding: BSmartSpacing.medium)

            Button {
                finishPrototypeConnection()
            } label: {
                HStack {
                    Image(systemName: "link")
                    Text(connectionButtonLabel)
                    Spacer()
                    Image(systemName: "checkmark")
                }
                .font(.headline)
                .foregroundStyle(BSmartColor.pulseInk)
                .padding(.horizontal, BSmartSpacing.large)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(BSmartColor.brand)
                .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("brokerage.finish-prototype")

            Text("Only selected U.S. equities enter the portfolio. Unsupported assets remain visible in this preview.".bSmartLocalized)
                .font(.caption2)
                .foregroundStyle(BSmartColor.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func connectedContent(_ account: LinkedBrokerageAccount) -> some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.xLarge) {
            VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
                HStack {
                    Label("Read-only prototype linked", systemImage: "checkmark.shield.fill")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(BSmartColor.brand)
                    Spacer()
                    Text("PROTOTYPE".bSmartLocalized)
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(BSmartColor.pulseInk)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(BSmartColor.pulse)
                        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control))
                }

                connectionMetric("Last refresh", value: account.lastSyncedAt.bSmartRelativeTimestamp)
                connectionMetric("Holdings detected", value: "\(account.detectedHoldingCount)")
                connectionMetric("Positions imported", value: "\(account.importedPositionCount)")
            }
            .bSmartSurface()

            Button {
                model.refreshBrokeragePrototype(provider)
            } label: {
                Label("Refresh connection preview", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
                isConfirmingDisconnect = true
            } label: {
                Label("Disconnect %@".bSmartLocalized(provider.displayName), systemImage: "link.badge.minus")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
        }
    }

    private func permissionRow(_ title: String, symbol: String, color: Color = BSmartColor.secondaryText) -> some View {
        Label {
            Text(title.bSmartLocalized)
                .font(.subheadline)
                .foregroundStyle(BSmartColor.primaryText)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 24)
        }
    }

    private func holdingRow(_ holding: BrokerageHoldingPreview) -> some View {
        Button {
            guard holding.isSupported else { return }
            if selectedTickers.contains(holding.ticker) {
                selectedTickers.remove(holding.ticker)
            } else {
                selectedTickers.insert(holding.ticker)
            }
        } label: {
            HStack(spacing: BSmartSpacing.medium) {
                BSmartAssetMark(ticker: holding.ticker, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: BSmartSpacing.small) {
                        Text(holding.ticker)
                            .font(.subheadline.weight(.bold))
                        Text((holding.isSupported ? "Supported" : "Preview only").bSmartLocalized)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(holding.isSupported ? BSmartColor.brand : BSmartColor.tertiaryText)
                    }
                    Text("%@ units · avg %@".bSmartLocalized(
                        holding.quantity.formatted(.number.precision(.fractionLength(0...4))),
                        holding.averageCost.formatted(.currency(code: "USD").precision(.fractionLength(0...2)))
                    ))
                        .font(.caption2)
                        .foregroundStyle(BSmartColor.secondaryText)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(holding.estimatedValue.formatted(.currency(code: "USD").precision(.fractionLength(0))))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                    if holding.isSupported {
                        Image(systemName: selectedTickers.contains(holding.ticker) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedTickers.contains(holding.ticker) ? BSmartColor.brand : BSmartColor.tertiaryText)
                    }
                }
            }
            .padding(.vertical, BSmartSpacing.small)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!holding.isSupported)
        .opacity(holding.isSupported ? 1 : 0.7)
    }

    private func connectionMetric(_ label: String, value: String) -> some View {
        HStack {
            Text(label.bSmartLocalized)
                .font(.caption)
                .foregroundStyle(BSmartColor.secondaryText)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
    }

    private var selectedSupportedHoldings: [BrokerageHoldingPreview] {
        provider.previewHoldings.filter { $0.isSupported && selectedTickers.contains($0.ticker) }
    }

    private var connectionButtonLabel: String {
        let count = selectedSupportedHoldings.count
        return count > 0
            ? "Link and import %d positions".bSmartLocalized(count)
            : "Link without importing positions".bSmartLocalized
    }

    private func previewAuthorization() {
        isAuthorizing = true
        Task {
            try? await Task.sleep(for: .milliseconds(850))
            guard !Task.isCancelled else { return }
            isAuthorizing = false
            withAnimation(BSmartMotion.standard) {
                isReviewingHoldings = true
            }
        }
    }

    private func finishPrototypeConnection() {
        let selected = selectedSupportedHoldings
        for holding in selected {
            _ = model.savePortfolioEntry(
                id: nil,
                ticker: holding.ticker,
                companyName: holding.name,
                kind: .position,
                shares: holding.quantity,
                averageCost: holding.averageCost,
                portfolioWeight: nil
            )
        }
        model.connectBrokeragePrototype(
            provider: provider,
            detectedHoldingCount: provider.previewHoldings.count,
            importedPositionCount: selected.count
        )
        onConnected?()
    }
}

struct BrokerageProviderBadge: View {
    let provider: BrokerageProvider
    let size: CGFloat

    var body: some View {
        Image(provider.logoAssetName)
            .resizable()
            .scaledToFit()
            .padding(size * provider.logoInset)
            .frame(width: size, height: size)
            .background(BSmartColor.elevated)
            .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
            .accessibilityLabel(provider.displayName)
    }
}

extension BrokerageProvider {
    var logoAssetName: String {
        switch self {
        case .robinhood: "Broker_Robinhood"
        case .interactiveBrokers: "Broker_IBKR"
        case .binance: "Broker_Binance"
        case .coinbase: "Broker_Coinbase"
        }
    }

    var logoInset: CGFloat {
        switch self {
        case .robinhood, .binance: 0.17
        case .interactiveBrokers, .coinbase: 0
        }
    }

    var coverageDescription: String {
        switch self {
        case .robinhood: "U.S. equities and supported balances"
        case .interactiveBrokers: "U.S. and global brokerage positions"
        case .binance: "Crypto balances and supported market exposure"
        case .coinbase: "Crypto balances and supported market exposure"
        }
    }

    var authorizationMethod: String {
        switch self {
        case .robinhood: "Provider authorization"
        case .interactiveBrokers: "Client Portal authorization"
        case .binance: "Read-only API credentials"
        case .coinbase: "Provider authorization"
        }
    }

    var previewHoldings: [BrokerageHoldingPreview] {
        [
            BrokerageHoldingPreview(ticker: "NVDA", name: "NVIDIA", quantity: 12, averageCost: 148.20, estimatedValue: 2_185, isSupported: true),
            BrokerageHoldingPreview(ticker: "NBIS", name: "Nebius", quantity: 16, averageCost: 41.80, estimatedValue: 812, isSupported: true),
            BrokerageHoldingPreview(ticker: "SPCX", name: "SPCX", quantity: 24, averageCost: 29.40, estimatedValue: 768, isSupported: true),
            BrokerageHoldingPreview(ticker: "SNDK", name: "Sandisk", quantity: 9, averageCost: 48.30, estimatedValue: 531, isSupported: true),
            BrokerageHoldingPreview(ticker: "SKHX", name: "SK Hynix", quantity: 7, averageCost: 112.60, estimatedValue: 861, isSupported: true),
            BrokerageHoldingPreview(ticker: "UNITREE", name: "Unitree", quantity: 12, averageCost: 36.20, estimatedValue: 492, isSupported: true),
        ]
    }
}
