import SwiftUI

struct TradingPositionsView: View {
    let wallet: DeviceWalletSummary
    @EnvironmentObject private var account: AccountAccessStore
    @State private var store: TradingPositionsStore?

    var body: some View {
        Group {
            if let store { TradingPositionsContent(wallet: wallet, store: store) }
            else { ProgressView() }
        }
        .task {
            if store == nil { store = TradingPositionsStore(service: account) }
        }
    }
}

private struct TradingPositionsContent: View {
    let wallet: DeviceWalletSummary
    @ObservedObject var store: TradingPositionsStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Open positions".bSmartLocalized).font(.headline)
                Spacer()
                Button { Task { await store.refresh(wallet: wallet) } } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
                }.disabled(store.isLoading).accessibilityLabel("Refresh".bSmartLocalized)
            }
            if store.isLoading { ProgressView() }
            if let error = store.errorMessage { Text(error).font(.subheadline).foregroundStyle(BSmartColor.bear) }
            if store.didLoad, store.rows.isEmpty, store.errorMessage == nil {
                Text("No open positions".bSmartLocalized).font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
            }
            ForEach(store.rows) { position in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        BSmartAssetMark(ticker: position.symbol, size: 32)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(position.coin).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                            Text("\((position.quantity.isNegative ? "Short" : "Long").bSmartLocalized) · \(position.leverage)x")
                                .font(.caption).foregroundStyle(position.quantity.isNegative ? BSmartColor.bear : BSmartColor.bull)
                        }
                        Spacer()
                        Text((position.unrealizedPnL.isNegative ? "-" : "+") + position.unrealizedPnL.magnitude.wire + " USDC")
                            .font(.subheadline.monospacedDigit()).foregroundStyle(position.unrealizedPnL.isNegative ? BSmartColor.bear : BSmartColor.bull)
                            .lineLimit(1).minimumScaleFactor(0.75)
                    }
                    HStack {
                        Text(position.quantity.magnitude.wire + " · " + (position.entryPrice?.wire ?? "--"))
                            .font(.caption.monospacedDigit()).foregroundStyle(BSmartColor.secondaryText)
                        Spacer()
                        NavigationLink {
                            LiveMarketOrderDestination(coin: position.coin, dex: position.dex,
                                side: position.quantity.isNegative ? .buy : .sell, initialReduction: true)
                                .padding(.horizontal, 20).navigationTitle(position.coin)
                        } label: {
                            Label("Reduce / Close".bSmartLocalized, systemImage: "minus.circle")
                                .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                        }.accessibilityIdentifier("wallet.position.close.\(position.coin)")
                    }
                    Divider()
                }
            }
        }
        .task { await store.refresh(wallet: wallet) }
        .onDisappear { store.clear() }
        .onChange(of: scenePhase) { _, phase in if phase == .background { store.clear() } }
        .accessibilityIdentifier("wallet.positions")
    }
}
