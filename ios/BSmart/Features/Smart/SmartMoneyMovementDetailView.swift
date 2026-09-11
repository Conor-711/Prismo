import SwiftUI

/// Keeps a selected movement readable even when its account is absent from the current leaderboard.
struct SmartMoneyMovementDetailView: View {
    @EnvironmentObject private var model: AppModel
    let movement: SmartMoneyMovement

    private var account: SmartMoneySignal? {
        model.smartMoney.first {
            $0.id.caseInsensitiveCompare(movement.accountId) == .orderedSame
                || $0.resolvedAddress.caseInsensitiveCompare(movement.accountId) == .orderedSame
        }
    }

    private var positionSide: String {
        switch movement.direction {
        case .bullish: "long position".bSmartLocalized
        case .bearish: "short position".bSmartLocalized
        case .neutral, .mixed: "position".bSmartLocalized
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 12) {
                    BSmartSmartMoneyAvatar(identity: movement.publicIdentity, size: 48)
                        .bSmartSubjectDestination(movement)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(movement.publicIdentity.displayName).font(.headline)
                        Text("Smart Money").font(.caption).foregroundStyle(BSmartColor.sky)
                    }
                    .bSmartSubjectDestination(movement)
                    Spacer()
                    BSmartAssetMark(ticker: movement.ticker, size: 36)
                }
                Text("\(movement.ticker) · \(movement.action.label) \(positionSide)")
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 16) {
                    fact("Market", value: movement.market)
                    fact("Observed at", value: movement.observedAt.bSmartDataTimestamp)
                    Divider().overlay(BSmartColor.line)
                    fact("Notional before", value: amount(movement.notionalBefore))
                    fact("Notional after", value: amount(movement.notionalAfter))
                    if let leverage = movement.leverage, leverage.isFinite && leverage > 0 {
                        fact("Leverage", value: leverage.formatted(.number.precision(.fractionLength(0...1))) + "x")
                    }
                }
                if let account {
                    BSmartDetailNavigationLink(id: "money-movement-account-\(movement.id)") {
                        SmartMoneyDetailView(signal: account)
                    } label: {
                        Label("Account activity".bSmartLocalized, systemImage: "person.crop.circle")
                    }
                    .tint(BSmartColor.sky)
                }
                if let url = movement.evidenceURL {
                    Link(destination: url) {
                        Label("Open evidence".bSmartLocalized, systemImage: "arrow.up.right.square")
                    }
                    .tint(BSmartColor.sky)
                }
            }
            .padding(BSmartSpacing.large)
        }
        .background(BSmartColor.ink)
        .foregroundStyle(BSmartColor.primaryText)
        .navigationTitle("Smart Money")
        .navigationBarTitleDisplayMode(.inline)
        .bSmartDetailPage()
        .bSmartPage()
        .accessibilityIdentifier("smart-money.movement-detail")
    }

    private func amount(_ value: Double) -> String {
        value.isFinite ? value.formatted(.bSmartDollars.precision(.fractionLength(0...2))) : "Unavailable".bSmartLocalized
    }

    private func fact(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label.bSmartLocalized).foregroundStyle(BSmartColor.secondaryText)
            Spacer(minLength: 8)
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}
