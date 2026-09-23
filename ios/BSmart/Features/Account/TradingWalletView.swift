import SwiftUI

struct TradingWalletView: View {
    @EnvironmentObject private var account: AccountAccessStore
    @EnvironmentObject private var wallet: DeviceWalletStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if account.identity == nil {
                    NavigationLink { TradingAccountView() } label: {
                        Label("Sign in".bSmartLocalized, systemImage: "person.crop.circle")
                            .font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                    }.accessibilityIdentifier("wallet.signin")
                } else {
                    DeviceWalletPanel()
                    if case .verified(let local) = wallet.state, local.canAuthorizeTransactions {
                        UnifiedAccountSetupView(wallet: local)
                        NavigationLink { TradingMarketsView() } label: {
                            Label("Trade perpetuals".bSmartLocalized, systemImage: "arrow.left.arrow.right")
                                .font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                                .foregroundStyle(BSmartColor.onAccent)
                                .background(BSmartColor.brand, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain).accessibilityIdentifier("wallet.trade")
                        TradingPositionsView(wallet: local)
                    }
                }
            }
            .padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        // Reserve space for the root's floating tab bar, including the last position's action.
        .safeAreaPadding(.bottom, 88)
        .background(BSmartColor.ink).foregroundStyle(BSmartColor.primaryText)
        .navigationTitle("Trading wallet".bSmartLocalized).navigationBarTitleDisplayMode(.inline)
        .task(id: "\(account.identity?.id.uuidString ?? "")-\(scenePhase == .background)") {
            guard scenePhase != .background, account.identity != nil else { return }
            await wallet.prepare()
        }
        .refreshable {
            guard !wallet.isBusy else { return }
            wallet.lock()
            await wallet.prepare()
        }
        .accessibilityIdentifier("wallet.screen")
        .bSmartPage()
    }
}
