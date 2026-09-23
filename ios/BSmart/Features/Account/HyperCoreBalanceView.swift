import Charts
import SwiftUI

struct HyperCoreBalanceView: View {
    let wallet: DeviceWalletSummary
    let compact: Bool
    let accountTitle: String
    let switchDestinationTitle: String
    let switchAccount: (() -> Void)?
    private let service: AccountWalletServicing
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var balances: HyperCoreBalanceStore
    @State private var refreshTask: Task<Void, Never>?
    @State private var historyTask: Task<Void, Never>?
    @State private var history: [PortfolioValuePoint]
    @State private var remoteHistory: [AccountBalancePeriod: [PortfolioValuePoint]] = [:]
    @State private var lastHistoryRequest: Date?
    @State private var lastDisplayedSnapshot: HyperCoreBalanceSnapshot?

    init(wallet: DeviceWalletSummary, service: AccountWalletServicing, compact: Bool = false,
         accountTitle: String = "bSmart account", switchDestinationTitle: String = "External holdings",
         switchAccount: (() -> Void)? = nil) {
        self.wallet = wallet
        self.compact = compact
        self.accountTitle = accountTitle
        self.switchDestinationTitle = switchDestinationTitle
        self.switchAccount = switchAccount
        self.service = service
        _balances = StateObject(wrappedValue: HyperCoreBalanceStore(service: service))
        _history = State(initialValue: AccountBalanceHistory.load(wallet: wallet))
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let current = balances.currentSnapshot(wallet: wallet, now: context.date)
            let pending = compact ? Self.snapshotWhileRefreshing(lastDisplayedSnapshot, wallet: wallet,
                accountMatches: service.walletAccountID == wallet.accountID,
                isLoading: balances.isLoading, now: context.date) : nil
            HyperCoreBalanceContent(snapshot: current ?? pending, expired: balances.snapshot != nil && current == nil,
                                    isLoading: balances.isLoading, errorMessage: balances.errorMessage,
                                    compact: compact, history: history, remoteHistory: remoteHistory,
                                    accountTitle: accountTitle, switchDestinationTitle: switchDestinationTitle,
                                    switchAccount: switchAccount) {
                refreshTask?.cancel()
                refreshTask = Task { await balances.refresh(wallet: wallet) }
            }
        }
        .task(id: "\(wallet.accountID)-\(wallet.address)-\(scenePhase == .active)") {
            guard compact, scenePhase == .active else { return }
            while !Task.isCancelled {
                await balances.refresh(wallet: wallet)
                do { try await Task.sleep(for: .seconds(25)) }
                catch { return }
            }
        }
        .onDisappear { clear() }
        .onChange(of: wallet) { _, current in
            clear()
            history = AccountBalanceHistory.load(wallet: current)
            remoteHistory = [:]
            lastHistoryRequest = nil
            lastDisplayedSnapshot = nil
        }
        .onChange(of: balances.snapshot) { _, snapshot in
            guard compact, let snapshot else { return }
            lastDisplayedSnapshot = snapshot
            history = AccountBalanceHistory.record(snapshot, wallet: wallet)
            let now = Date()
            guard lastHistoryRequest.map({ now.timeIntervalSince($0) >= 300 }) ?? true else { return }
            lastHistoryRequest = now
            historyTask?.cancel()
            historyTask = Task {
                guard let points = try? await AccountBalanceHistory.remote(wallet: wallet), !Task.isCancelled,
                      !points.isEmpty else { return }
                remoteHistory = points
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { clear() } }
        .accessibilityIdentifier(compact ? "portfolio.account.balance" : "wallet.hypercore-balances")
    }

    private func clear() {
        refreshTask?.cancel(); refreshTask = nil
        historyTask?.cancel(); historyTask = nil
        balances.clear()
        lastDisplayedSnapshot = nil
    }

    static func snapshotWhileRefreshing(_ previous: HyperCoreBalanceSnapshot?, wallet: DeviceWalletSummary,
                                        accountMatches: Bool, isLoading: Bool, now: Date) -> HyperCoreBalanceSnapshot? {
        guard let previous, accountMatches, isLoading,
              previous.accountID == wallet.accountID, previous.owner == wallet.address,
              (0..<45).contains(now.timeIntervalSince(previous.checkedAt)) else { return nil }
        return previous
    }
}

struct HyperCoreBalanceContent: View {
    let snapshot: HyperCoreBalanceSnapshot?
    let expired: Bool
    let isLoading: Bool
    let errorMessage: String?
    var compact = false
    var history: [PortfolioValuePoint] = []
    var remoteHistory: [AccountBalancePeriod: [PortfolioValuePoint]] = [:]
    var accountTitle = "bSmart account"
    var switchDestinationTitle = "External holdings"
    var switchAccount: (() -> Void)? = nil
    let refresh: () -> Void
    @State private var selectedPeriod: AccountBalancePeriod = .day
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selectedHistory: [PortfolioValuePoint] {
        if let remote = remoteHistory[selectedPeriod], remote.count >= 2 { return remote }
        return selectedPeriod.localPoints(in: history, now: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !compact {
                HStack {
                    Text("On Hyperliquid".bSmartLocalized)
                        .font(.headline).foregroundStyle(BSmartColor.primaryText)
                    Spacer(minLength: 12)
                    refreshButton
                }
            }
            if compact {
                HStack(spacing: 8) {
                    Text(snapshot?.accountBalanceValue.map { $0.formatted(.bSmartDollars.precision(.fractionLength(2))) } ?? "--")
                        .font(.system(size: 38, weight: .semibold))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.55), value: snapshot?.accountBalanceValue)
                        .accessibilityIdentifier("portfolio.account.balance-value")
                    Spacer(minLength: 0)
                    if let switchAccount {
                        PortfolioAccountSwitchButton(currentTitle: accountTitle,
                                                     nextTitle: switchDestinationTitle,
                                                     action: switchAccount)
                    }
                }
                HStack(spacing: 4) {
                    ForEach(AccountBalancePeriod.allCases) { period in
                        Button { selectedPeriod = period } label: {
                            Text(period.rawValue.bSmartLocalized)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(selectedPeriod == period ? BSmartColor.primaryText : BSmartColor.secondaryText)
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .background(selectedPeriod == period ? BSmartColor.elevated : .clear,
                                            in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selectedPeriod == period ? .isSelected : [])
                        .accessibilityIdentifier("portfolio.account.period.\(period.rawValue)")
                    }
                }
                AccountBalanceChart(history: selectedHistory)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: selectedHistory)
            } else if let snapshot {
                Text(snapshot.mode.title).font(.subheadline.weight(.medium)).foregroundStyle(BSmartColor.brand)
                row(snapshot.mode.usesSharedBalance ? "USDC balance" : "Spot USDC", amount: snapshot.usdc.formatted)
                row("USDC on hold", amount: snapshot.held.formatted)
                if let perps = snapshot.perps {
                    Divider().overlay(BSmartColor.line)
                    row("Default perps equity", amount: perps.equity.formatted)
                    row("Default perps withdrawable", amount: perps.withdrawable.formatted)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("Checked".bSmartLocalized)
                    Spacer(minLength: 12)
                    Text(snapshot.checkedAt, style: .time).monospacedDigit()
                }.font(.caption).foregroundStyle(BSmartColor.secondaryText)
            } else {
                Text((expired ? "Balance check expired" : "Not checked").bSmartLocalized)
                    .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                    .accessibilityIdentifier(expired ? "wallet.hypercore-expired" : "wallet.hypercore-unchecked")
            }
            if let errorMessage {
                Text(compact ? "Balance unavailable. Try again.".bSmartLocalized : errorMessage)
                    .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("wallet.hypercore-error")
            }
            if !compact {
                Text("Balances do not confirm an individual deposit or the amount available for a new trade.".bSmartLocalized)
                .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var refreshButton: some View {
        Button(action: refresh) {
            if isLoading { ProgressView().frame(width: 44, height: 44) }
            else { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }
        }
        .buttonStyle(.plain).foregroundStyle(BSmartColor.brand).disabled(isLoading)
        .accessibilityLabel(compact ? "Refresh".bSmartLocalized : "Check Hyperliquid balances".bSmartLocalized)
        .accessibilityIdentifier("wallet.check-hypercore-balances")
    }

    private func row(_ title: String, amount: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(title.bSmartLocalized).fixedSize().foregroundStyle(BSmartColor.secondaryText)
                Spacer(minLength: 0)
                Text(amount).fixedSize().monospacedDigit().fontWeight(.semibold)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(title.bSmartLocalized).foregroundStyle(BSmartColor.secondaryText)
                Text(amount).monospacedDigit().fontWeight(.semibold)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.subheadline).foregroundStyle(BSmartColor.primaryText)
        .accessibilityElement(children: .combine)
    }
}

private struct AccountBalanceChart: View {
    let history: [PortfolioValuePoint]

    private var range: ClosedRange<Double> {
        let values = history.map(\.value)
        let minimum = values.min() ?? 0
        let maximum = values.max() ?? 1
        let padding = max((maximum - minimum) * 0.15, maximum * 0.003, 0.01)
        return (minimum - padding)...(maximum + padding)
    }

    var body: some View {
        Chart {
            ForEach(history) { point in
                if history.count > 1 {
                    AreaMark(x: .value("Date", point.timestamp), yStart: .value("Base", range.lowerBound),
                             yEnd: .value("Balance", point.value))
                        .foregroundStyle(LinearGradient(colors: [BSmartColor.brand.opacity(0.18), .clear],
                                                        startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Date", point.timestamp), y: .value("Balance", point.value))
                        .foregroundStyle(BSmartColor.brand)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                } else {
                    PointMark(x: .value("Date", point.timestamp), y: .value("Balance", point.value))
                        .foregroundStyle(BSmartColor.brand).symbolSize(30)
                }
            }
        }
        .chartYScale(domain: range)
        .chartXAxis(.hidden).chartYAxis(.hidden)
        .frame(height: 104)
        .overlay {
            if history.count < 2 {
                Text("No valuation history".bSmartLocalized)
                    .font(.caption).foregroundStyle(BSmartColor.tertiaryText)
            }
        }
        .accessibilityIdentifier("portfolio.account.balance-chart")
    }
}
